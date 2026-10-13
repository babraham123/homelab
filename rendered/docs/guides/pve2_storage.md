# pve2 storage: the media array

Four HDDs on a PCIe SATA card passed through whole to websvcs, snapraid for parity, mergerfs for one
mount point.

- The HDDs hold media only: not backed up, parity is their protection
- PBS stays on the SATA SSD on the onboard controller; games stay on the gaming VM's NVMe until a
  second SSD arrives (`backup-and-dr/14`)
- Everything here is run by hand once. The repo carries only what must match the disks afterwards:
  - `websvcs.media.disks` in `vars.yml`
  - from it `src/services/snapraid/snapraid.conf.j2`, `media.fstab.j2` and the snapraid timers,
    installed by `install_snapraid`
- The pool is always `/srv/media`

## Hardware prerequisites

- A PCIe SATA controller with at least four ports (ASM1166 class)
  - It sits beside the RTX 3060 Ti and the Tesla P4: check the free slot is x1 or better and the
    card is **alone in its IOMMU group** (step 2)
  - The Kontron K3843-B's four onboard ports share one controller with the PBS SSD and the Blu-ray
    drive, so the onboard controller can't be passed through
- Mounting for four 3.5" drives and six SATA power connectors from the RM550x (its bundle has eight)
- Power: four HDDs add ~25 W running, ~90 W during spin-up. Cap the GPU (`nvidia-smi -pl 180` in the
  gaming VM) or the CPU's PL2 in the BIOS to keep transients off the 550 W ceiling
- Remove the old, unused HDD first: `lsblk` on the host, confirm no mount, no `/etc/fstab` entry and
  no PVE storage (`pvesm status`), then pull it

## 1. Install the disks

- With pve2 off: card in the slot, the four HDDs on the card, SSD and Blu-ray on the onboard ports
- Boot and note the disks

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL
ls -l /dev/disk/by-id/ | grep -v part
```

## 2. Pass the controller through

- The card's PCI address and IOMMU group; the group must hold only the card

```bash
/root/homelab-rendered/src/base/debian/iommu_groups.sh | grep -i -B1 -A1 sata
```

- IOMMU and vfio are already on for the GPU ([Proxmox guide, GPU](./proxmox.md#gpu)). Bind the card
  to vfio at boot so the host never claims the disks

```bash
lspci -nn -s ADDRESS         # the [vendor:device] id
echo 'options vfio-pci ids=VENDOR:DEVICE' > /etc/modprobe.d/sata-passthrough.conf
update-initramfs -u -k all && reboot
```

- After the reboot, `lspci -k -s ADDRESS` shows `Kernel driver in use: vfio-pci` and the HDDs are
  gone from `lsblk`
- Attach the card to websvcs

```bash
qm set $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs) --hostpci1 ADDRESS,pcie=1
qm stop $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs) && qm start $(/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh websvcs)
```

- Passthrough pins the VM's memory and blocks live migration and `qm snapshot`; vzdump snapshot-mode
  backups are unaffected

## 3. Partition and format, inside websvcs

- The disks show their real `ata-*` ids and SMART works
- One ext4 partition per disk, labelled by role; `-m 0` since nothing on them runs as root

```bash
ls -l /dev/disk/by-id/ata-*  | grep -v part
for d in disk1 disk2 disk3 parity; do
  dev=/dev/disk/by-id/ata-SERIAL_FOR_$d          # one at a time, by hand
  parted -s "$dev" mklabel gpt mkpart primary ext4 0% 100%
  mkfs.ext4 -m 0 -L "$d" "${dev}-part1"
done
```

## 4. Declare the disks and install

- In `vars.yml`, `websvcs.media.disks`: one entry per disk with its `ata-*` id and mount point; the
  one under `/mnt/parity` is parity

```bash
tools/deploy_src.sh
ssh autoadmin@websvcs install_snapraid
```

- On websvcs, append the rendered fstab fragment and mount

```bash
mkdir -p /mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/parity /srv/media
cat /root/homelab-rendered/src/services/snapraid/media.fstab >> /etc/fstab
systemctl daemon-reload && mount -a
df -h /mnt/disk* /mnt/parity /srv/media
```

## 5. First sync

```bash
snapraid sync          # builds parity from scratch; hours for full disks, seconds when empty
snapraid status
systemctl list-timers 'snapraid-*'
```

- `snapraid-sync.timer` syncs daily, `snapraid-scrub.timer` scrubs weekly, both through
  `snapraid_run.sh`
- A sync is refused when more than 200 files disappeared since the last one (`threshold` in
  `snapraid_run.sh`)
- `homelab_snapraid_last_success_timestamp_seconds` and `homelab_smart_healthy` reach
  VictoriaMetrics via node_exporter; `src/services/vmalert/configs/backups.yml` alerts on both

## Day to day

- Media goes under `/srv/media`; mergerfs puts new files on the disk with the most free space.
  Services read the pool, never `/mnt/disk*`
  - `archive/linkding`, `archive/readeck`: page snapshots and archived articles
  - `books/narrate`, `books/readalouds`: Calliope's inbox, work and output; `books/storyteller`:
    Storyteller's processed books and uploads
  - Databases stay on the VM disk under `/var/opt`: SQLite over mergerfs is unsafe
- **A disk failed** ([manual](https://www.snapraid.it/manual#recover)):
  1. Replace it and format as in step 3, same label and mount point
  2. Update its id in `vars.yml`, `tools/deploy_src.sh`, then
     `ssh autoadmin@websvcs install_snapraid` to reinstall `/etc/snapraid.conf`
  3. On websvcs, replace the disk's line in `/etc/fstab` with the new one from
     `/root/homelab-rendered/src/services/snapraid/media.fstab`, then
     `systemctl daemon-reload && mount -a`
  4. On websvcs: `snapraid fix -d dN` for a data disk; `snapraid sync -F` then `snapraid fix` for
     the parity disk
- **Mass delete on purpose** (over the threshold): `snapraid sync --force-empty`, or raise the
  threshold and run `snapraid_run.sh sync`
- SMART details: `smartctl -a /dev/disk/by-id/ata-...` on websvcs; `smartd` logs to the journal
