# 14. Second SSD on pve2 for the gaming and devtop data disks

Status: resolved
Type: task
Repo: homelab
Source: backup restructure grilling 2026-10-04

## Problem

Games live on the gaming VM's system disk on the 1 TB NVMe, so every weekly image backup reads and
hashes them, and the NVMe is shared with every other VM on pve2.

## Plan (decided)

- A new SSD (NVMe in the board's second M.2 slot, or SATA on the passthrough card's spare port)
  becomes an LVM-thin pool, PVE storage `local-games`.
- `qm set gaming --scsi1 local-games:350,backup=0,discard=on,ssd=1` and
  `qm set devtop --scsi1 local-games:100,backup=0,discard=on,ssd=1`; games move to the D: drive,
  devtop's bulk data to the new disk. `backup=0` keeps both out of vzdump: pve2's `backup.sh images`
  then backs up only the system disks. A restored VM comes back without the data disk; the restore
  guide says how to re-attach it.
- The migration (Windows D: setup, moving Steam libraries, devtop mounts) goes into
  `docs/guides/pve2_storage.md` as a new section when the disk exists.

## Needs

Which SSD, and whether it goes in M.2 (then the existing "Storage" row in `docs/architecture.md`
changes) or on the SATA card (then it lands inside websvcs with the passthrough, which rules it
out). Decide, buy, then flip to ready-for-human.

## Comments

- 2026-11-01: resolved without a second SSD. The games disk lives on pve2's existing NVMe pool:
  gaming's OS disk was shrunk to 96 GiB and a 500 GiB `scsi1` (`local-lvm`, `backup=0`) holds the
  games, so the weekly image backs up only the OS disk. devtop and websvcs were shrunk to 96 GiB and
  devtop gets no data disk. The pool is allocated without overcommit. The shared-NVMe concern stays;
  a second SSD can still take the games disk later. Shrink steps are in `docs/guides/vm.md`, the
  re-attach in `docs/guides/restore.md`.
