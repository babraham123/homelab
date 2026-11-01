# General Proxmox VM setup

Guide to create and manage a VM. Includes optimal Proxmox settings, network configuration and backup
setup. Docs: [config files](https://pve.proxmox.com/wiki/Proxmox_Cluster_File_System_(pmxcfs))

## VM creation

[ref](https://www.youtube.com/watch?v=sZcOlW-DwrU)

- Upload OS ISO image, use net install version
- For UEFI host:
  - Machine: q35
  - BIOS: OVMF
  - EFI Storage: local-lvm, Pre-Enroll keys (Secure Boot with Microsoft's 2023 certificates,
    `ms-cert=2023k` on `efidisk0`)
- SCSI controller: VirtIO SCSI single
- Disk (host SSD)
  - Check node's lvm-thin pool for total available disk
  - SSD emulation
  - Discard (if storage supports thin provisioning and zeroing of unused space: ZFS, Ceph, thin LVM)
- CPU
  - type: host
  - max cores = host cores - 1
- Memory
  - Ballooning device (ensure the memory is always available, don't overcommit)
- OS installation
  - Use ext4, no lvm, all files in 1 partition
    [ref](https://forum.proxmox.com/threads/lvm-or-ext4-on-kvm-guest.39055/)

Reference links:

- [Display devices](https://www.kraxel.org/blog/2019/09/display-devices-in-qemu/)
- [BIOS](https://www.reddit.com/r/Proxmox/comments/1acugae/bios_or_uefi_for_linux_vms_for_performance/)
- [Storage](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_storage)

Maintenance:

- [Resize disks](https://pve.proxmox.com/wiki/Resize_disks#Online_for_Linux_guests_without_LVM)
- [Secure Boot certificates](#secure-boot-certificates)
- [Shrink a disk](#shrink-a-disk)

### Secure Boot certificates

Microsoft's 2011 UEFI certificates expire in 2026. An older EFI disk holds only those;
`qm enroll-efi-keys` adds the 2023 ones and sets `ms-cert=2023k`. VMs without pre-enrolled keys
(Secure Boot off) need nothing.

```bash
# On the Proxmox host as root, VM stopped
qm config VMID | grep efidisk0              # no ms-cert=2023k: needs the update
qm stop VMID && qm enroll-efi-keys VMID && qm start VMID
qm config VMID | grep efidisk0              # ms-cert=2023k
```

- Check in a Linux guest: `mokutil --sb-state` says SecureBoot enabled,
  `mokutil --db | grep -c 'UEFI CA 2023'` is at least 1
- Record `ms-cert=2023k` in the node's `qm.conf.template`

### Shrink a disk

Proxmox only grows disks. Shrinking is offline, from the host, with a snapshot to roll back to. Back
up the VM first, and check the guest's used space fits well under the new size.

- Stop the VM, snapshot it, map the disk's partitions

```bash
# On the Proxmox host as root
qm stop VMID && qm snapshot VMID pre-shrink
LOOP=$(losetup -fP --show /dev/pve/vm-VMID-disk-N); lsblk -o NAME,SIZE,FSTYPE $LOOP
```

- Shrink the last filesystem to a little under the target, so the GPT backup header fits after it
  - ext4: `e2fsck -f ${LOOP}pN` (run it again if it exits 1 after fixing counters), then
    `resize2fs ${LOOP}pN 94G`
  - NTFS: `ntfsresize --info ${LOOP}pN` for the minimum, `ntfsresize --no-action -s 94G ${LOOP}pN`,
    then without `--no-action`. Windows' own Shrink Volume stops at unmovable files like
    `$Mft::$BITMAP`; delete its shadow copies first if it must be used.
- Recreate the partition with the same start, type and GUID, ending at least 1 MiB before the new
  size (`sgdisk -i N $LOOP` before deleting; an NTFS partition's GUID is the Windows volume GUID),
  then `partprobe $LOOP` and `losetup -d $LOOP`
  - A swap partition after the root partition: recreate it inside the GPT's last usable sector
    (`sgdisk -p`), then `mkswap -U OLD_UUID` so fstab still finds it
- Shrink the LV. This thin LVM doesn't discard blocks past the new end on `lvreduce`, so discard
  them first or the pool keeps them allocated

```bash
blkdiscard -f -o $((96 * 1024**3)) /dev/pve/vm-VMID-disk-N   # -f: the GPT signature makes it refuse
lvreduce -y -L 96G pve/vm-VMID-disk-N
qm rescan --vmid VMID                                       # config size= follows the LV
```

- Fix the GPT for the smaller disk and grow the filesystem back to fill the partition

```bash
LOOP=$(losetup -fP --show /dev/pve/vm-VMID-disk-N)
sgdisk -e $LOOP && partprobe $LOOP
# ext4: resize2fs ${LOOP}pN    NTFS: ntfsresize -f ${LOOP}pN (its own shrink set the chkdsk flag)
losetup -d $LOOP
```

- Start the VM and check it boots. Windows: `fsutil dirty query C:`; if dirty, `chkdsk C: /f` and
  restart. Then delete the snapshot with `qm delsnapshot VMID pre-shrink`. Leave the snapshot's
  `unusedN` entries alone: `qm set VMID --delete unusedN` destroys the volume.

## pfSense config

- Record the MAC address from Proxmox, Hardware >> Network Device
- Create a static DHCP lease in pfSense
  - Go to Services >> DHCP Server >> PVE# >> DHCP Static Mappings
- Add a DNS record
  - Update `unbound.conf`
  - Go to Services >> DNS Resolver >> Custom options, paste in config

## Backups

- Don't add PVE backup jobs; the weekly run images every VM
  ([Services](../services.md#storage-and-backups))
- Restores: [restore guide](./restore.md)
