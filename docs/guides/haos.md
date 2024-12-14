# Home Assistant setup [deprecated]
Initial setup for a Home Assistant VM.

## VM creation
[Ref1](https://forum.proxmox.com/threads/guide-install-home-assistant-os-in-a-vm.143251/), [ref2](https://getlabsdone.com/how-to-import-qcow2-into-proxmox-server-step-by-step/), [ref3](https://pve.proxmox.com/wiki/OVMF/UEFI_Boot_Entries)

- Do the basic [VM setup](./vm.md), except
  - OS: Do not use any media
  - System: uncheck Pre-Enroll keys (disable secure boot)
  - Disks: delete all disks
- Import the qcow2 file
```bash
HA_VERSION=$(curl -s "https://api.github.com/repos/home-assistant/operating-system/releases/latest" | grep -Po '"tag_name": "\K[0-9.]+')
wget "https://github.com/home-assistant/operating-system/releases/download/${HA_VERSION}/haos_ova-${HA_VERSION}.qcow2.xz"
unxz "haos_ova-${HA_VERSION}.qcow2.xz"

vm_id=$(sudo /usr/local/bin/get_vm_id.sh homesvcs)
sudo qm importdisk "$vm_id" haos_ova-${HA_VERSION}.qcow2 local-lvm
rm haos_ova*
```
- Attach the new disk
  - Go to homesvcs >> Hardware >> Unused disk 0 >> Edit
  - Select options from [VM setup](./vm.md) and press Add
  - Go to homesvcs >> Options >> Boot Order >> Edit
  - Enable scsi0 and make it first
- Use `lsusb` to detect any USB devices and pass them through to the VM, [ref](https://pve.proxmox.com/wiki/USB_Devices_in_Virtual_Machines).
- Start the VM
- Navigate to `http://home.{{ site.url }}:8123`

## Add supporting services

- Go to homesvcs >> Console
```bash
login
curl http://192.168.4.154:8181/id_ed25519.pub >> /root/.ssh/authorized_keys
systemctl enable --now dropbear
exit
```

```bash
rm -r temp
ssh root@homesvcs.{{ site.url }} -p 22222
passwd root
dnf install openssh-server
systemctl enable sshd
systemctl start sshd
```
