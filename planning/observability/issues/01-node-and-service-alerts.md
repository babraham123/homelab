# 01. Add vmalert rules for hosts, disks, systemd units, backups and auth

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 18
Blocked by: backup-and-dr/01

## Problem

All 35 rules in `src/vmalert/configs/` are VictoriaMetrics self-monitoring.

## Change

New file `src/vmalert/configs/homelab.yml` (`install_svcs.sh vmalert` already copies
`configs/*.yml`). Rules, all with `severity` labels that Alertmanager already routes:

**Hosts (node_exporter, all VMs + pve1/pve2):**
- `NodeDown`: `up{job=~"node_exporter.*"} == 0` for 5m
- `DiskAlmostFull`: `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.10` (exclude tmpfs/overlay)
- `DiskFillingIn24h`: `predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0`
- `MemoryPressure`: `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10` for 10m
- `HighLoad`: `node_load15 / count(node_cpu_seconds_total{mode="idle"}) without(cpu,mode) > 2` for 15m
- `HighCpuTemp`: `node_hwmon_temp_celsius > 85` for 5m (pve1 is fanless)
- `SystemdUnitFailed`: `node_systemd_unit_state{state="failed"} == 1` for 5m —
  `src/node_exporter/node_runner.sh:17` already passes `--collector.systemd`, filtered by
  `--collector.systemd.unit-include="($SVC_LIST)\.service"`, so only the units in
  `SVC_LIST` are visible; check that list covers every quadlet on each node (and the
  orchestrator/updater timers once they exist). This is also the cheapest "container
  restart loop" signal since quadlets are systemd units
- `ClockSkew`: `abs(node_timex_offset_seconds) > 0.5`

**Backups (from the orchestrator's textfile metric, backup-and-dr/01):**
- `BackupStale`: `time() - homelab_backup_last_success_timestamp_seconds > 8*86400`
- `BackupNeverRan`: `absent(homelab_backup_last_success_timestamp_seconds)`

**Scrape health:** `TargetDown`: `up == 0` for 5m (generic, excluding gaming/devtop).

**Authelia:** `AuthFailureBurst`:
`increase(authelia_authentication_first_factor_total{success="false"}[10m]) > 20`
(verify the exact metric name against the current Authelia `/metrics`).

**Gatus as the second path:** `EndpointDown`: `gatus_results_endpoint_success == 0` for 15m.

Add a `homelab.json` Grafana dashboard or a row in `node_exporter.json` showing the
firing state. Document the list in `docs/services.md#observability`.

## Acceptance

- `vmalert` loads the file without error; `SystemdUnitFailed` fires when a quadlet is
  deliberately broken; `DiskAlmostFull` fires with `fallocate` on a test VM.

## Comments

- 2026-09-27: backup-and-dr/01 landed. The metric is
  `homelab_backup_last_success_timestamp_seconds{job="pg_dumpall"|"backup_hass"|"vzdump_pve1"|"vzdump_pve2"}`,
  from `/var/lib/node_exporter/textfile_collector/homelab_backup.prom` on pve1 (scraped
  as `pve1.<site>:9100`). A failed step keeps its old timestamp, so `BackupStale` fires
  per job; the run is weekly, so 8 days is right. `backup_orchestrator.service` is a
  "Homelab:" unit, so `SystemdUnitFailed` also catches a failed run.

- 2026-10-04: the backup rules landed with the backup restructure as
  `src/vmalert/configs/backups.yml` (`BackupStale`, `BackupNeverRan`, plus
  `SnapraidStale` and `DiskUnhealthy` for the media array). The orchestrator's job
  labels are now `backup_<node>` and `upload`. Leave backups
  out of `homelab.yml`.
