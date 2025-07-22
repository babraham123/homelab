# Proxmox setup

## Hardware & Network
- Setup dedicated LAN in pfSense
  - Open admin console: https://{{ router.ip }}/
  - Configure new interface (PVE#), record gateway details
  - Setup DHCP in `[100,200]` range, add static IP based on MAC
  - Copy firewall rules from LAN
- Make a [flash drive](https://www.lewan.com/blog/2012/02/10/making-a-bootable-usb-stick-on-an-apple-mac-os-x-from-an-iso) with proxmox [iso](https://www.proxmox.com/en/downloads/category/iso-images-pve) and install
  - F2 during startup to select USB boot
- Test connection: https://{{ pve2.ip }}:8006/ 

## PVE setup
- Shell in with root, password
- Update deb repository, [src](https://it42.cc/2019/10/14/fix-proxmox-repository-is-not-signed/) 
  - `nano /etc/apt/sources.list`, add `contrib non-free non-free-firmware` to all 3 sources
  - `nano /etc/apt/sources.list.d/pve-enterprise.list`
```
#deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
```
- Basic [Debian Linux setup](./debian.md)
- Install special tools
```bash
sudo wget https://enterprise.proxmox.com/debian/proxmox-release-bullseye.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
sudo apt install -y libguestfs-tools intel-microcode
```
- Collect system stats to help with VM selection 
```bash
# Show which CPUs are P (performance) vs E (efficiency)
lscpu --all --extended
# Show total / free RAM
free -h
# Show disk size
lsblk
```

## PCI passthrough
[src](https://pve.proxmox.com/wiki/PCI_Passthrough)

### GPU
- Update grub
```bash
# Check if grub or systemd-boot
efibootmgr -v
sudo vim /etc/default/grub
```

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt initcall_blacklist=sysfb_init"
```
```bash
sudo update-grub
```
- Update modules
```bash
sudo vim /etc/modules
```
```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

```bash
sudo vim /etc/modprobe.d/pve-blacklist.conf
```
```
blacklist nvidiafb
blacklist nvidia
blacklist radeon
blacklist nouveau

blacklist snd_hda_intel
blacklist snd_hda_codec_hdmi
```
- Update BIOS settings
  - Under CPU, confirm that VT-d and VT-x/VMX are enabled
  - Under Graphics, make the iGPU the Primary Display
- Confirm its works and find PCI id
```bash
sudo reboot
# Confirm that IOMMU is enabled
sudo dmesg | grep -e DMAR -e IOMMU
# Confirm that remapping is enabled
sudo dmesg | grep 'remapping'
# Confirm dedicated IOMMU groups / ACS support, record GPU group #
find /sys/kernel/iommu_groups/ -type l | sort
# record GPU PCI IDs
lspci -nnv | grep VGA
lspci -s 01:00 && lspci -s 01:00 -n
```

### iGPU
- Same as above, [ref](https://3os.org/infrastructure/proxmox/gpu-passthrough/igpu-passthrough-to-vm/#linux-virtual-machine-igpu-passthrough-configuration)
- `sudo vim /etc/modprobe.d/pve-blacklist.conf`
```
blacklist i915
```
```bash
sudo reboot
lspci -nnv | grep VGA
```

### Intel NIC
- Fix crashes
	- `sudo vim /etc/network/interfaces`
```
iface eno1 inet manual
	post-up ethtool -K eno1 tso off gso off
```

### Coral TPU
- Update modules
  `sudo vim /etc/modprobe.d/blacklist-apex.conf`
```
blacklist gasket
blacklist apex
options vfio-pci ids=1ac1:089a
```
```bash
sudo reboot
lspci -nnv | grep TPU
```
- In VM setup, uncheck "Pre-Enroll keys" in BIOS
- If doesn't work, consider `pcie_aspm=off`
  [ref1](https://github.com/blakeblackshear/frigate/issues/1020), [ref2](https://forum.proxmox.com/threads/guest-internal-error-when-passing-through-pcie.99239/), [ref3](https://www.derekseaman.com/2023/06/home-assistant-frigate-vm-on-proxmox-with-pcie-coral-tpu.html)

## USB Passthrough

- Pass thru physical port, [docs](https://pve.proxmox.com/wiki/USB_Physical_Port_Mapping)
  - Get the port details
```bash
sudo su
# Get dev number from device description
lsusb
# Get bus and port number
lsusb -t
```
  - In PVE UI, Go to VM >> Hardware >> Add USB device
  - Reboot the VM

## VM management
[Docs](https://pve.proxmox.com/pve-docs/qm.1.html)

- Watchdog to prevent stuck VM
```bash
sudo su
src/debian/install_svcs.sh vm_watchdog
```

- Other tools
```bash
cp src/pve2/get_vm_id.sh /usr/local/bin
```

## Networking
- Remove unnecessary services (not using HA mode)
```bash
systemctl disable --now pve-ha-crm.service
systemctl disable --now pve-ha-lrm.service
systemctl disable --now corosync.service
```

- Firewall setup, [PVE ports](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#_ports_used_by_proxmox_ve)
```bash
ufw default allow routed
ufw allow in from any to any port 22,8006,3128 proto tcp
ufw allow in from any to any port 5900:5999 proto tcp
ufw allow in from any to any port 111 proto udp
# Excludes corosync and live migration ports
ufw enable
```

## Backups
Only installed on PVE2. [Ref](https://pve.proxmox.com/wiki/Backup_and_Restore)

- Update deb repository
  - `vim /etc/apt/sources.list.d/pbs-enterprise.list`
```
# NOT recommended for production use
deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription
```
- Install PBS, [ref](https://pbs.proxmox.com/docs/installation.html)
```bash
apt update
apt install -y proxmox-backup-server
ufw allow in from any to any port 8007 proto tcp
```
- Connect to console: https://{{ pve2.ip }}:8007/ 
- Further [setup](https://www.youtube.com/watch?v=33ubleU4OFc), [setup2](https://www.youtube.com/watch?v=Px5eHcUKbbQ)
  - Storage >> Directory >> Create: Directory
  - Datastore >> backup1 >> Prune & GC tab, [options](https://pbs.proxmox.com/docs/maintenance.html)
    - Prune Jobs >> Add >> Last weekly: 3, last monthly: 3, daily
    - Garbage Collection >> Edit >> daily

- PVE setup
  - Datacenter >> Storage >> Add >> Proxmox Backup Server
  - VM >> Backup >> Backup now
  - Datacenter >> Backup >> Add
    - Exclude fingerprint for Let's Encrypt derived PBS certs
    - For the schedule I picked Sunday at 1am (pve1), 2am (pve2)

- PVE / PBS backups
TODO: flesh this out
```bash
tar -czf "etc-backup-$(date -I).tar.gz" /etc
```

## Monitoring
- Install Node Exporter
```bash
adduser node_exporter --system
groupadd node_exporter
usermod -a -G node_exporter node_exporter
cd /root/homelab-rendered
src/debian/install_svcs.sh node_exporter
```

- Allow access from metrics container in order to scrape node_exporter
```bash
# Use {{ secsvcs.ip }} on pve1, {{ websvcs.ip }} on pve2
ufw allow in from {{ secsvcs.ip }} to any port 9100 proto tcp
```

- Create an API user in the PVE console (for pve1, pve2 and pbs2)
  - Go to Datacenter >> Permissions >> Users >> Add, name = api_ro
  - Go to Permissions >> Add >> User Permission
  - path = /, user = api_ro@pam, role = PVEAuditor, propagate = check
  - For PBS, Permissions -> Access Control, PVEAuditor -> Audit. Generate a user password:
```bash
ssh {{ username }}@pve1.{{ site.url }}
sudo /root/homelab-rendered/src/pve1/secret_update.sh pve1
```

Perform these steps after pve1, secsvcs and victoriametrics is configured (do this for pve1, pve2 and pbs2). [Ref](https://pve.proxmox.com/wiki/External_Metric_Server)
- Get the metrics admin password and hash credentials
```bash
ssh {{ username }}@secsvcs.{{ site.url }}
password=$(sudo /usr/local/bin/get_secret.sh victoriametrics_admin_password)
echo -n "admin:$password" | base64
```
- Go to Datacenter >> Metric Server >> Add >> InfluxDB
- For PBS, go to Configuration >> Metric Server >> Add >> InfluxDB (HTTP)
- Set:
  - server = metrics.{{ site.url }}
  - port = 443
  - protocol = https
  - organization = proxmox
  - bucket = proxmox
  - token = CREDS_HASH

## Upgrade

### Minor version
Consider pinning the kernel version
- [PVE 8.4 guide](https://pve.proxmox.com/wiki/Downloads#Update_a_running_Proxmox_Virtual_Environment_8.x_to_latest_8.4)
```bash
sudo su
apt update
apt dist-upgrade
reboot
pveversion -v
systemctl status proxmox-backup-proxy.service proxmox-backup.service
```

### From PVE 7 to 8 (bullseye to bookworm)
- Make sure the VM backups are up to date
- [PVE guide](https://pve.proxmox.com/wiki/Upgrade_from_7_to_8)
- [PBS guide](https://pbs.proxmox.com/wiki/index.php/Upgrade_from_2_to_3#In-place_Upgrade)
```bash
sudo su
pve7to8 --full
apt update
apt dist-upgrade
pveversion
sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list
sed -i -e 's/bullseye/bookworm/g' /etc/apt/sources.list.d/*.list
apt update
apt dist-upgrade
pve7to8 --full
[ -d /sys/firmware/efi ] && sudo apt install grub-efi-amd64
systemctl reboot

sudo su
systemctl status proxmox-backup-proxy.service proxmox-backup.service
pve7to8 --full
apt update
apt upgrade
```
