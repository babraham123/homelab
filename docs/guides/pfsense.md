# pfSense setup on Proxmox
Setups PVE1 from scratch to run pfsense as a VM on proxmox. You probably want a combo wifi/router on hand as backup in case you run into any issues.

## Install Proxmox
- Make a [usb installer](https://www.lewan.com/blog/2012/02/10/making-a-bootable-usb-stick-on-an-apple-mac-os-x-from-an-iso) with proxmox [iso](https://www.proxmox.com/en/downloads/category/iso-images-pve)
```bash
cd Downloads
hdiutil convert -format UDRW -o proxmox.img proxmox-ve_8.0-2.iso
mv proxmox.img.dmg proxmox.img
diskutil list
diskutil unmountDisk /dev/disk2
sudo dd if=proxmox.img of=/dev/rdisk2 bs=1m
diskutil eject /dev/disk2
```
- Change boot order to favor USB via BIOS (press F2)
- Boot and run thru installer
- Shell in with root, password
- Connect to network directly for installs, plug eth0 into existing router, [src](https://www.cyberciti.biz/faq/setting-up-an-network-interfaces-file/)
  - `sudo nano /etc/network/interfaces`
```
auto enp2s0
iface enp2s0 inet dhcp
```
`systemctl restart networking`
- Test connection: `ping 1.1.1.1`
- Add proxmox repo, [src](https://it42.cc/2019/10/14/fix-proxmox-repository-is-not-signed/)
  - `sudo nano /etc/apt/sources.list.d/pve-enterprise.list`
```
#deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
```
- Install desktop env, [src](https://pve.proxmox.com/wiki/Developer_Workstations_with_Proxmox_VE_and_X11)
```bash
sudo su
rm /etc/apt/sources.list.d/ceph.list
apt update && apt upgrade
apt install -y xfce4 chromium lightdm sudo ufw
adduser {{ username }}
usermod -aG sudo {{ username }}
ip addr
systemctl start lightdm
# login, reboot
```
- Basic [debian setup](./debian.md)

## Install pfSense
- Connect to pve console: https://HOST_IP_ADDR:8006/
- Upload pfSense ISO using USB, [src](https://www.virtualizationhowto.com/2022/08/pfsense-proxmox-install-process-and-configuration/)
- Create VM
  - 64GB disk, 4 cores, 4GB memory, no network
  - startup order 1, ssd emulation, discard=1, cache=none
- Enable IOMMU / NIC passthrough, [src](https://www.servethehome.com/how-to-pass-through-pcie-nics-with-proxmox-ve-on-intel-and-amd/)
  - BIOS >> Advanced >> CPU Configuration >> VMX >> Enabled
`efibootmgr -v` # is grub or systemd
`nano /etc/default/grub`
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```
`update-grub && reboot`
`nano /etc/modules`
```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```
```bash
reboot
dmesg | grep -e DMAR -e IOMMU | grep able
dmesg | grep remapping
lspci
```
- Add passed thru NICs to VM, via [PCI passthru](https://pve.proxmox.com/wiki/PCI(e)_Passthrough)
  - VM >> Hardware >> Add >> PCI Device >> Raw Device >> [pick hw id]
  - `lspci -nn -vvv | grep Ethernet` # get hw id
- Pass in a bridge iface as Network Device (see below)
- Plug eth0 into modem, eth1 to WiFi AP
- Start VM and run thru pfSense install via Console, [src](https://www.virtualizationhowto.com/2022/08/pfsense-proxmox-install-process-and-configuration/)
  - UFS, GPT
  - Assign Interfaces: WAN=igc0, LAN=igc1, rest as optional
  - Optional: Set Interface IPs (LAN)
    - `{{ lan.subnet }}.[100 - 200]/24`
- Log into pfSense GUI
  - Connect eth1 (LAN) directly to laptop
  - Connect to admin console via LAN ip address (192.168.1.1)
  - Go thru Setup Wizard
    - name: router, etc
  - GUI address will change to {{ router.ip }}
- Setup WiFi AP
  - `http://tplinkeap.net/`
  - Set all SSIDs to use WPA-Personal, WPA2-PSK security
    - Go to Wireless >> Wireless Settings
    - For each SSID >> Action >> click the edit icon
  - Backup settings
    - Go to System >> Backup & Restore >> click Backup
- Test connectivity / DNS issues, [src](https://docs.netgate.com/pfsense/en/latest/troubleshooting/connectivity.html)
  - Disabled IPv6 and DNSSEC (for now) 
- Enable auto backup (ACB)

### QEMU Agent
[ref](https://forum.netgate.com/topic/162083/pfsense-vm-on-proxmox-qemu-agent-installation/6)
- Go to System >> Advanced >> Admin Access >> Secure Shell
  - Check Enable Secure Shell
- Install and enable agent
```bash
ssh admin@router.{{ site.url }}
pkg install -y qemu-guest-agent
nano /etc/rc.conf.local
nano /usr/local/etc/rc.d/qemu-agent.sh
chmod +x /usr/local/etc/rc.d/qemu-agent.sh
service qemu-guest-agent start
```

### System Patches
Apply security updates and fixes since the last release
- Go to System >> Package Manager
- Install the System_Patches package
- Go to System >> Patches
- Click "Apply All Recommended"

### Bufferfloat
Improve latency when under heavy load
- Follow all the steps listed [here](https://docs.netgate.com/pfsense/en/latest/recipes/codel-limiters.html). That includes:
  - Run the load test
  - Create a download limiter and queue
  - Create an upload limiter and queue
  - Create a floating rule

## Networking

### Share connectivity with the PVE host and other VMs
- Configure `vmbr0` to be static, use the LAN network and have no physical interface. 
  - Paste in `src/pve1/interfaces`
    - `sudo nano /etc/network/interfaces`
  - Paste in `src/pve1/resolv.conf`
    - `sudo nano /etc/resolv.conf`
- In pfSense,
	- Attach `vmbr0` as a network device
	- Enable the interface as a LAN with a static address
	- Enable the DHCP service, create a static lease for each PVE host
    - Go to Services >> DHCP Server >> PVE1 >> DHCP Static Mappings
	- Copy the firewall rules from an existing LAN and apply them
- Reboot the host

### Custom subdomains
- Go to Services >> DNS Resolver
- Add host overrides
- On your computer (MacOS), go to Settings >> Network >> Wi-Fi >> Details >> DNS
  - Delete the old DNS Servers
  - Add {{ router.ip }}, 1.1.1.1 (Chrome only uses 8.8.8.8 if it's present in the list)
  - Add `{{ site.url }}` to Search Domains

For local-only overrides of existing routes
- Go to Services >> DNS Resolver
- Set "System Domain Local Zone Type" to "Redirect"
- Paste `unbound.conf` into "Custom options"

### Automations
- Setup cert import
```bash
wget https://raw.githubusercontent.com/stompro/pfsense-import-certificate/master/pfsense-import-certificate.php
scp pfsense-import-certificate.php admin@router.{{ site.url }}:/root
rm pfsense-import-certificate.php
```
  - Remove the default cert
    - Go to System >> Certificates >> Certificates
    - delete `webConfigurator default`
- Setup API access, [Ref](https://github.com/jaredhendrickson13/pfsense-api)
```bash
# Reinstall after update
pkg -C /dev/null add https://github.com/jaredhendrickson13/pfsense-api/releases/latest/download/pfSense-2.7-pkg-API.pkg && /etc/rc.restart_webgui
```

Networking ref:
- https://docs.netgate.com/pfsense/en/latest/recipes/virtualize-proxmox-ve.html#basic-proxmox-ve-networking 
- https://forum.proxmox.com/threads/proxmox-isp-modem-without-a-router.105338/
- https://forum.proxmox.com/threads/proxmox-management-interface-and-pfsense.120231/ 
- https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking# 
- https://pve.proxmox.com/wiki/Network_Configuration 
- https://pve.proxmox.com/pve-docs/chapter-sysadmin.html#_choosing_a_network_configuration 

VM sizing ref:
- https://docs.netgate.com/pfsense/en/latest/hardware/size.html 
- https://www.intel.com/content/www/us/en/products/sku/212328/intel-celeron-processor-n5105-4m-cache-up-to-2-90-ghz/specifications.html 
- https://www.reddit.com/r/Proxmox/comments/u3imdm/how_bad_is_the_overcommitting_of_cpu_and_memory/ 
- https://www.aliexpress.us/item/3256804315368607.html?spm=a2g0o.order_detail.order_detail_item.3.3a7cf19cWI0ORL&gatewayAdapt=glo2usa&_randl_shipto=US 

Other ref:
- https://www.servethehome.com/new-fanless-4x-2-5gbe-intel-n5105-i226-v-firewall-tested/ 
- https://pve.proxmox.com/wiki/Pci_passthrough 
- https://pve.proxmox.com/wiki/SPICE 

### mDNS
[src](https://forums.lawrencesystems.com/t/avahi-with-google-chromecast-on-pfsense/2074/4)
- Go to System >> Package Manager
- Install the Avahi package
- Go to Services >> Avahi
- Enable daemon, Action = allow, select internal interfaces (not WAN), Enable reflection

### Ad Block
[ref](https://www.youtube.com/watch?v=xizAeAqYde4)
- Go to System >> Package Manager
- Install the pfBlockerNG-devel package
- Go to Firewall >> pfBlockerNG
- Run thru wizard
  - inbound interface = internet facing, outbound = internal LAN ones
  - Ensure the VIP Address does not lie within any networks
- Geo data:
  - Register for a MaxMind acct
  - Go to IP, add license key and account id

## PVE1 remaining setup
Execute the following sections from the [proxmox guide](./proxmox.md):
- VM Management
- Networking
- Monitoring

## Monitoring
Upload to Victoria Metrics:
- Get the metrics admin password from secsvcs
  `/usr/local/bin/get_secret.sh victoriametrics_admin_password`
- Install the plugins
```bash
cd src/pfsense/plugins
chmod 555 telegraf_*
scp telegraf_* admin@router.{{ site.url }}:/usr/local/bin
```
- Go to System >> Package Manager
- Install the Telegraf package
- Go to Services >> Telegraf
- Set Enable, Telegraf Output = `InfluxDB`, InfluxDB Server = `https://metrics.{{ site.url }}`, InfluxDB Database = pfsense, InfluxDB Username = admin, InfluxDB Password
- In Additional configuration, paste in `telegraf.conf` 

Monitor traffic flows, [ref](https://www.youtube.com/watch?v=P8oxTUoF2Nw):
- Go to System >> Package Manager
- Install the nmap package
- Install the ntopng, ntopng-data package
- Go to Diagnostics >> ntopng Settings
- Set ntopng Admin Password, select all interfaces
- Use MaxMind key from above
- Leave this disabled unless you want to investigate an issue

Watch for new devices:
- Go to System >> Package Manager
- Install the ARPwatch package
- Go to Service >> ARPwatch
- Add {{ site.email }} to "Notifications recipient"
- Set "Enable Arpwatch"

Service Watchdog:
- Go to System >> Package Manager
- Install the Service Watchdog package
- Go to Services >> Service Watchdog
- Add all of the services present (especially Tailscale and sshd)
