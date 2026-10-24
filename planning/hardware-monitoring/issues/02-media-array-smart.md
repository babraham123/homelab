# 02. Per-disk SMART metrics, dashboard and alerts for the media array

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-23

## Problem

The array's only health signal is `homelab_smart_healthy`, a daily `smartctl -H` pass/fail
written by `snapraid_run.sh`. A disk shows trouble in its attributes (reallocated and pending
sectors, CRC errors, heat) long before `-H` fails, and a disk under a new SATA card and new
cables is most likely to show CRC errors first.

## Change

1. **Exporter**, installed by websvcs's `install_snapraid`, enabled only once
   `websvcs.media.disks` has real ids:
   - `smartctl_exporter` from the latest GitHub release, checked against its `sha256sums.txt`
     (the `nvidia_gpu_exporter` pattern)
   - `src/services/snapraid/smartctl_exporter.service.j2`: root (raw device access), one
     `--smartctl.device=/dev/disk/by-id/<id>` per declared disk so the VM's virtual disks aren't
     scanned, default `--smartctl.powermode-check=standby`, `:9633`, sandboxed. Its `device` label
     is the by-id name, the same as `homelab_smart_healthy`'s.
   - ufw: from vmagent (`.7`) to 9633, in `docs/guides/pve2_storage.md.j2`
2. **Scrape job** `smartctl` in `src/nodes/websvcs/prometheus.yml.j2`, like `nvidia_gpu`.
3. **Alerts**, group `disks` in `hardware.yml` (01):
   - `DiskUnhealthy`, moved from `backups.yml`, now `smartctl_device_smart_status == 0`
   - `DiskHot`: `smartctl_device_temperature{temperature_type="current"} > 50` for 15m, warning;
     WD Red Plus drives are rated to 65°C, and sustained heat over 50 shortens their life
   - `DiskSectorsGrowing`: any of `Reallocated_Sector_Ct`, `Current_Pending_Sector`,
     `Offline_Uncorrectable`, `Reported_Uncorrect` (raw) rose in the last day, error
   - `DiskCrcErrors`: `UDMA_CRC_Error_Count` (raw) rose in the last day, warning: the cable or the
     card, not the disk
4. **Drop** `smart_health()` from `snapraid_run.sh.j2`; the exporter replaces it.
5. **Dashboard** `src/services/grafana/dashboards/disks.json`: per-disk SMART table (model,
   serial, health, temperature, power-on time, the sector and CRC counters), temperature over
   time, throughput and utilisation from node_exporter for websvcs's `sd*` disks, per-mount space,
   and the age of the last snapraid sync and scrub.
6. **Docs**: `docs/services.md` (host services row, alert list), `pve2_storage.md.j2`.

## Acceptance

- `curl -s localhost:9633/metrics | grep smartctl_device_smart_status` on websvcs lists all four
  disks.
- `up{job="smartctl"} == 1`; the dashboard fills.
- A spun-down disk stays spun down (`hdparm -C`) across a few polls.

## Comments

- 2026-10-23: code in. `smartctl_exporter.service.j2` and its install in websvcs's `snapraid`
  case (enabled only with disks declared), the `smartctl` scrape job (rendered only with disks
  declared, so `TargetDown` stays quiet until then), group `disks` in `hardware.yml` with
  `DiskUnhealthy` moved there, `smart_health()` dropped from `snapraid_run.sh.j2`, `disks.json`
  ("Disks"), ufw step in `pve2_storage.md.j2`. Acceptance waits for the array to be installed.
