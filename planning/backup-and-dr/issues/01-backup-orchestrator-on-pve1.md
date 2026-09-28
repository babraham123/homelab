# 01. Backup orchestrator on pve1 that wakes pve2

Status: claimed
Type: task
Repo: homelab
Source: review finding 1, 2
Blocked by: 07, 08

## Problem

PBS (`pbs2`) lives on pve2, which is powered off most of the time. PVE's own backup
schedule (`docs/guides/proxmox.md.j2:223`, Sunday 01:00 pve1 / 02:00 pve2) silently
no-ops when pve2 is down. Nothing coordinates "wake the target, run every backup, copy
offsite, power down".

## Change

Add `src/pve1/backup_orchestrator.sh` + `backup_orchestrator.{service,timer}`, installed
via `src/pve1/install_svcs.sh backup_orchestrator` (new case + dispatcher entry).

Sequence:

1. `ssh autoadmin@router start_pve2` (already exists), then `wait_reachable pbs2 600`
   from `src/base/lib.sh` (restructure/03; until that lands, loop over
   `is_reachable.sh pbs2` with the same timeout); abort + alert via ntfy if pve2 never
   comes up.
2. Run application dumps first, so they land inside the VM disks before vzdump:
   `ssh autoadmin@secsvcs pg_dumpall` (issue 07), `ssh autoadmin@homesvcs backup_hass`
   (issue 08).
3. `vzdump` the pve1 VMs to the `backup1` datastore (local, pve1 is root).
4. `ssh autoadmin@pve2 run_backups` (new pve2 dispatcher cmd wrapping `vzdump` for
   websvcs/devtop/gaming; gaming is skipped if the VM is off).
5. Trigger the offsite copy (issue 03).
6. Write `homelab_backup_last_success_timestamp_seconds{job="..."}` to the
   node_exporter textfile collector directory on pve1 so vmalert can alert on staleness
   (observability/01).
7. `ssh autoadmin@pve2 shutdown` (already exists) unless pve2 was already on when the run
   started.

Every step logs to the journal and posts a one-line ntfy summary at the end (success or
the step that failed). Keep the Gatus maintenance window in `src/gatus/config.yaml.j2`
aligned with the timer.

## Acceptance

- Timer fires with pve2 off; pve2 boots, all VMs on both hosts get a fresh PBS snapshot,
  pve2 powers off afterwards.
- A run with pve2 unreachable exits non-zero and posts an ntfy alert.
- `homelab_backup_last_success_timestamp_seconds` visible in VictoriaMetrics.

## Notes

- Future: the same orchestrator will also back up plain files (media, `/root/secrets`
  export, etc.). Structure the script as a list of named steps so adding one is one
  function.
- `vm_watchdog.sh` on pve1/pve2 may fight a deliberate power-down; check it before
  wiring step 7.

## Comments
