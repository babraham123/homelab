# pve2 storage: the media array
Four HDDs on a PCIe SATA card, the card passed through whole to websvcs, snapraid for parity and mergerfs for one mount point. The HDDs hold media only; nothing on them is backed up, parity is their protection. PBS stays on the SATA SSD on the onboard controller, and games stay on the gaming VM's NVMe disk until a second SSD arrives (`backup-and-dr/14`).

Everything on this page is run by hand once. The repo only carries what has to match the disks afterwards: `websvcs.media.disks` in `vars.yml`, and from it `src/snapraid/snapraid.conf.j2`, `media.fstab.j2` and the snapraid timers, installed by `install_snapraid`. The pool is always `/srv/media`.

## Hardware prerequisites
- A PCIe SATA controller with at least four ports (ASM1166 class). It sits beside the RTX 3060 Ti and the Tesla P4, so check the free slot is x1 or better and that it is **alone in its IOMMU group** (step 2) before relying on it. The Kontron K3843-B has four onboard SATA ports, all on one controller with the PBS SSD and the Blu-ray drive, so the onboard controller cannot be passed through.
- Mounting for four 3.5" drives and six SATA power connectors from the RM550x (its bundle has eight). Four HDDs add ~25 W running and ~90 W during spin-up; the 550 W supply has room, but cap the GPU (`nvidia-smi -pl 180` in the gaming VM) or the CPU's PL2 in the BIOS to keep transients off the ceiling.
- Remove the old, unused HDD first. On the host: `lsblk`, confirm it has no mount, no entry in `/etc/fstab` and no PVE storage (`pvesm status`), then pull it.

## 1. Install the disks
With pve2 off: card in the slot, the four HDDs on the card, SSD and Blu-ray left on the onboard ports. Boot and note the disks:
```bash
lsblk -o NAME,SIZE,MODEL,SERIAL
ls -l /dev/disk/by-id/ | grep -v part
```

## 2. Pass the controller through
```bash
# The card's PCI address and IOMMU group; the group must hold only the card
/root/homelab-rendered/src/debian/iommu_groups.sh | grep -i -B1 -A1 sata
```
IOMMU and vfio are already on for the GPU ([the Proxmox guide](./proxmox.md), "IOMMU"). Bind the card to vfio at boot so the host never claims the disks:
```bash
lspci -nn -s ADDRESS         # the [vendor:device] id
echo 'options vfio-pci ids=VENDOR:DEVICE' > /etc/modprobe.d/sata-passthrough.conf
update-initramfs -u -k all && reboot
```
After the reboot `lspci -k -s ADDRESS` shows `Kernel driver in use: vfio-pci` and the four HDDs are gone from `lsblk`. Attach the card to websvcs:
```bash
qm set $(/usr/local/bin/get_vm_id.sh websvcs) --hostpci1 ADDRESS,pcie=1
qm stop $(/usr/local/bin/get_vm_id.sh websvcs) && qm start $(/usr/local/bin/get_vm_id.sh websvcs)
```
A passthrough device pins the VM's memory and blocks live migration and `qm snapshot`; vzdump snapshot-mode backups are unaffected.

## 3. Partition and format, inside websvcs
The disks appear with their real `ata-*` ids and SMART works. One partition per disk, ext4, label by role:
```bash
ls -l /dev/disk/by-id/ata-*  | grep -v part
for d in disk1 disk2 disk3 parity; do
  dev=/dev/disk/by-id/ata-SERIAL_FOR_$d          # one at a time, by hand
  parted -s "$dev" mklabel gpt mkpart primary ext4 0% 100%
  mkfs.ext4 -m 0 -L "$d" "${dev}-part1"
done
```
`-m 0`: no reserved blocks; nothing on these disks runs as root.

## 4. Declare the disks and install
In `vars.yml`, `websvcs.media.disks`: one entry per disk with its `ata-*` id and mount point; the one mounted under `/mnt/parity` is parity. Then:
```bash
tools/deploy_src.sh
ssh autoadmin@websvcs install_snapraid
```
On websvcs, append the rendered fstab fragment and mount:
```bash
mkdir -p /mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/parity /srv/media
cat /root/homelab-rendered/src/snapraid/media.fstab >> /etc/fstab
systemctl daemon-reload && mount -a
df -h /mnt/disk* /mnt/parity /srv/media
```

## 5. First sync
```bash
snapraid sync          # builds parity from scratch; hours for full disks, seconds when empty
snapraid status
systemctl list-timers 'snapraid-*'
```
From here `snapraid-sync.timer` syncs daily and `snapraid-scrub.timer` scrubs weekly, both through `snapraid_run.sh`, which refuses a sync when more than 200 files disappeared since the last one (`threshold` in `snapraid_run.sh`). `homelab_snapraid_last_success_timestamp_seconds` and `homelab_smart_healthy` land in VictoriaMetrics via node_exporter; `src/vmalert/configs/backups.yml` alerts on both.

## Day to day
- Media goes under `/srv/media`; mergerfs places new files on the disk with the most free space. Services read the pool, never `/mnt/disk*`.
- **A disk failed**: replace it, format as in step 3 with the same label and mount point, update its id in `vars.yml`, redeploy, then on websvcs `snapraid fix -d dN` (data) or `snapraid fix` after `snapraid sync -F` for the parity disk. [Manual: recovering](https://www.snapraid.it/manual#recover).
- **Mass delete on purpose** (over the threshold): `snapraid sync --force-empty`, or run `snapraid_run.sh sync` after raising the threshold.
- SMART details: `smartctl -a /dev/disk/by-id/ata-...` on websvcs; `smartd` logs to the journal.
