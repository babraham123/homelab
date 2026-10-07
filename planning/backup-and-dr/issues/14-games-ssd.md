# 14. Second SSD on pve2 for the gaming and devtop data disks

Status: needs-info
Type: task
Repo: homelab
Source: backup restructure grilling 2026-10-04

## Problem

Games live on the gaming VM's system disk on the 1 TB NVMe, so every weekly image
backup reads and hashes them, and the NVMe is shared with every other VM on pve2.

## Plan (decided)

- A new SSD (NVMe in the board's second M.2 slot, or SATA on the passthrough card's
  spare port) becomes an LVM-thin pool, PVE storage `local-games`.
- `qm set gaming --scsi1 local-games:350,backup=0,discard=on,ssd=1` and
  `qm set devtop --scsi1 local-games:100,backup=0,discard=on,ssd=1`; games move to the
  D: drive, devtop's bulk data to the new disk. `backup=0` keeps both out of vzdump:
  pve2's `backup.sh images` then backs up only the system disks. A restored VM comes
  back without the data disk; the restore guide says how to re-attach it.
- The migration (Windows D: setup, moving Steam libraries, devtop mounts) goes into
  `docs/guides/pve2_storage.md` as a new section when the disk exists.

## Needs

Which SSD, and whether it goes in M.2 (then the existing "Storage" row in
`docs/architecture.md` changes) or on the SATA card (then it lands inside websvcs with
the passthrough, which rules it out). Decide, buy, then flip to ready-for-human.

## Comments
