# 13. Media array on pve2: HDDs on a passed-through SATA card, snapraid + mergerfs in websvcs

Status: ready-for-human
Type: task
Repo: homelab
Source: backup restructure grilling 2026-10-04

## Problem

The four WD HDDs are bought and not installed. Media has nowhere to live but the VM
disks on the NVMe, which the weekly image backup then carries to PBS.

## Decisions (from the grilling)

- The HDDs go on a PCIe SATA card, and the **card is passed through whole to websvcs**
  (`hostpci`), so the guest sees real `ata-*` disks and SMART works there. The onboard
  controller keeps the PBS SATA SSD and the Blu-ray drive, and cannot be passed
  through. Prerequisite: the card alone in its IOMMU group.
- Inside websvcs: **snapraid, 1 parity (the disk in `websvcs.media.disks` mounted under `/mnt/parity`),
  mergerfs** over the data disks at `/srv/media`, options
  `cache.files=off,category.create=pfrd,func.getattr=newest,minfreespace=50G,moveonenospc=true`.
- **Media is not backed up**; parity is its protection. The disks are `backup=0`
  implicitly (passthrough) and `backup.sh files` on websvcs excludes the pool.
- PBS stays on the SATA SSD; games stay on the gaming VM's NVMe disk (14). No share to
  other VMs for now.
- `vars.yml` holds only each disk's by-id and mount point. Partitioning, mkfs, fstab,
  the first sync and the `qm set` passthrough are manual, in the guide.
- `snapraid-sync.timer` daily, `snapraid-scrub.timer` weekly (8% of blocks older than
  10 days), both via `snapraid_run.sh`, which refuses a sync when more than
  200 files vanished (`threshold` in `snapraid_run.sh`). Metrics
  `homelab_snapraid_last_success_timestamp_seconds{job}` and `homelab_smart_healthy{device}`
  through node_exporter's textfile dir; alerts in `src/vmalert/configs/backups.yml`.
- Remove the old unused HDD first. Hardware: SATA card, mounting for four drives, six
  SATA power leads; the RM550x is enough with the GPU power-capped.

## Code (done)

`src/snapraid/` (`snapraid.conf.j2`, `media.fstab.j2`, `snapraid_run.sh.j2`, the four
units), `install_snapraid` in `src/websvcs/install_svcs.sh` (listed under websvcs
`services` in `nodes.yml`; timers are only enabled once `websvcs.media.disks` is set),
`websvcs.media.disks` in `vars.template.yml`, `docs/guides/pve2_storage.md`.

## Human steps

Follow `docs/guides/pve2_storage.md` top to bottom. Acceptance: `snapraid status` clean
after the first sync, `systemctl list-timers 'snapraid-*'` shows both timers,
`homelab_snapraid_last_success_timestamp_seconds{job="sync"}` and four
`homelab_smart_healthy` series in VictoriaMetrics, and `ssh autoadmin@websvcs
backup` stages nothing from the pool.

## Comments
