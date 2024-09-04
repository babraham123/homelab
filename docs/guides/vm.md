# General Proxmox VM setup
Guide to create and manage a VM. Includes optimal Proxmox settings, network configuration and backup setup.

## VM creation
[ref](https://www.youtube.com/watch?v=sZcOlW-DwrU)
- Upload OS ISO image, use net install version
- For UEFI host:
  - Machine: q35
  - BIOS: OVMF
- SCSI controller: VirtIO SCSI single
- Disk (host SSD)
  - SSD emulation
  - Discard (if storage supports thin provisioning and zeroing of unused space: ZFS, Ceph, thin LVM)
- CPU
  - type: host
  - max cores = host cores - 1
- OS installation
  - Use ext4, no lvm, all files in 1 partition [ref](https://forum.proxmox.com/threads/lvm-or-ext4-on-kvm-guest.39055/)

Reference links:
- [Display devices](https://www.kraxel.org/blog/2019/09/display-devices-in-qemu/)
- [BIOS](https://www.reddit.com/r/Proxmox/comments/1acugae/bios_or_uefi_for_linux_vms_for_performance/)
- [Storage](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_storage)

Maintenance:
- [Resize disks](https://pve.proxmox.com/wiki/Resize_disks#Online_for_Linux_guests_without_LVM)

## pfSense config
- Create a static DHCP lease
  - Go to Services >> DHCP Server >> PVE# >> DHCP Static Mappings

- Add a DNS record
  - Update `unbound.conf`
  - Go to Services >> DNS Resolver >> Custom options, paste in config

## Backups
- VM >> Backup >> Backup now
- Datacenter >> Backup >> Add
