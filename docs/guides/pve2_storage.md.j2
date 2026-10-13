# pve2 storage: the media array

Four HDDs on a PCIe SATA card passed through to websvcs; snapraid parity, mergerfs pool at
`/srv/media`.

- Media only, not backed up
- Disks are declared in `vars.yml` (`websvcs.media.disks`); `install_snapraid` installs the config,
  fstab fragment and timers

## Hardware prerequisites

- PCIe SATA controller, 4+ ports (ASM1166 class), alone in its IOMMU group (step 2)
  - The onboard controller also serves the PBS SSD and Blu-ray drive, so it can't be passed through
- Mounts for four 3.5" drives, six SATA power connectors from the RM550x
- Power: HDDs add ~25 W running, ~90 W at spin-up. Cap the GPU (`nvidia-smi -pl 180` in the gaming
  VM) or the CPU's PL2
- Remove the old HDD: check `lsblk`, `/etc/fstab` and `pvesm status` for any use, then pull it

## 1. Install the disks

- With pve2 off: card in a free x1+ slot, HDDs on the card, SSD and Blu-ray on the onboard ports
- Boot and note the disks

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL
ls -l /dev/disk/by-id/ | grep -v part
```

## 2. Pass the controller through

- Find the card's PCI address; its IOMMU group must hold only the card

```bash
/root/homelab-rendered/src/base/debian/iommu_groups.sh | grep -i -B1 -A1 sata
```

- Bind it to vfio at boot (IOMMU is on from the [Proxmox guide](./proxmox.md#gpu))

```bash
lspci -nn -s ADDRESS         # the [vendor:device] id
echo 'options vfio-pci ids=VENDOR:DEVICE' > /etc/modprobe.d/sata-passthrough.conf
update-initramfs -u -k all && reboot
```

- Check: `lspci -k -s ADDRESS` shows `vfio-pci`, and the HDDs are gone from `lsblk`
- Attach the card to websvcs

```bash
qm set $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs) --hostpci1 ADDRESS,pcie=1
qm stop $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs) && qm start $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs)
```

## 3. Partition and format, inside websvcs

```bash
ls -l /dev/disk/by-id/ata-*  | grep -v part
for d in disk1 disk2 disk3 parity; do
  dev=/dev/disk/by-id/ata-SERIAL_FOR_$d          # one at a time, by hand
  parted -s "$dev" mklabel gpt mkpart primary ext4 0% 100%
  mkfs.ext4 -m 0 -L "$d" "${dev}-part1"
done
```

## 4. Declare the disks and install

- In `vars.yml`, `websvcs.media.disks`: each disk's `ata-*` id and mount point; `/mnt/parity` is
  parity

```bash
tools/deploy_src.sh
ssh autoadmin@websvcs install_snapraid
```

- On websvcs, mount

```bash
mkdir -p /mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/parity /srv/media
cat /root/homelab-rendered/src/services/snapraid/media.fstab >> /etc/fstab
systemctl daemon-reload && mount -a
df -h /mnt/disk* /mnt/parity /srv/media
```

## 5. First sync

```bash
snapraid sync          # hours for full disks, seconds when empty
snapraid status
systemctl list-timers 'snapraid-*'
```

- Timers: daily sync, weekly scrub, via `snapraid_run.sh`; a sync stops if 200+ files disappeared
- Alerts: `src/services/vmalert/configs/backups.yml`

## Day to day

- Services use `/srv/media`, never `/mnt/disk*`; databases stay under `/var/opt`
  - `archive/linkding`, `archive/readeck`
  - `books/narrate`, `books/readalouds`, `books/storyteller`
- A disk failed ([manual](https://www.snapraid.it/manual#recover)):
  1. Replace it and format as in step 3, same label and mount point
  2. Update its id in `vars.yml`, `tools/deploy_src.sh`, `ssh autoadmin@websvcs install_snapraid`
  3. On websvcs, replace its `/etc/fstab` line from
     `/root/homelab-rendered/src/services/snapraid/media.fstab`, then
     `systemctl daemon-reload && mount -a`
  4. On websvcs: `snapraid fix -d dN` for a data disk; `snapraid sync -F` then `snapraid fix` for
     parity
- Intentional mass delete: `snapraid sync --force-empty`
- SMART: `smartctl -a /dev/disk/by-id/ata-...` on websvcs; `smartd` logs to the journal
