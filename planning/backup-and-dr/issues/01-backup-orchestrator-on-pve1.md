# 01. Backup orchestrator on pve1 that wakes pve2

Status: resolved
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

## Answer

2026-09-27: `src/pve1/backup_orchestrator.sh.j2` + `.service.j2` (oneshot, 6h timeout) +
`.timer` (Sun 01:00, `Persistent=true`), installed by
`ssh autoadmin@pve1 install_backup_orchestrator` (`backup_orchestrator: {}` under pve1
`services` in `src/nodes.yml`; only the timer is enabled).

- **Steps.** `wake_pve2` → `STEPS=(pg_dumpall backup_hass vzdump_pve1 vzdump_pve2)` →
  `sleep_pve2`. Each is a `step_<name>` function run in an errexit subshell; adding a
  backup is one function plus one `STEPS` entry. Only a `wake_pve2` failure skips the
  rest; any other failure is recorded and the run continues, so one broken dump doesn't
  cost the VM snapshots.
- **Wake.** `start_pve2` on the router, then `is_reachable.sh pbs2` (600s), then
  `pvesm status --storage pbs2` reporting `active` (300s), since a pingable host isn't a
  running PBS. `src/base/lib.sh` doesn't exist yet (restructure/03 is still open), so the
  script carries its own `wait_for`; restructure/03 should swap it for `wait_reachable`.
- **vzdump.** pve1: `vzdump --all --storage pbs2 --mode snapshot` (router, secsvcs,
  homesvcs). pve2: new `run_backups` dispatcher command in `src/pve2/commands.sh.j2` backs
  up websvcs plus whichever of devtop/gaming is running. Backing up the stopped one
  starts it, and the hookscript would then stop the running one (shared GPU), so this
  applies to devtop too, not only gaming.
- **Metrics.** `homelab_backup_last_success_timestamp_seconds{job="<step>"}` in
  `/var/lib/node_exporter/textfile_collector/homelab_backup.prom` (atomic rename). A
  failed step keeps its previous timestamp, so staleness alerts fire per job.
- **Sleep.** `ssh autoadmin@pve2 shutdown` only if pve2 was off when the run started,
  then waits up to 300s for it to stop answering ping; a host that stays up fails the
  `sleep_pve2` step.
- **Notify.** One ntfy post to `push.<site>/alert` with `ntfy_alert_token` (read from
  `/root/secrets/secsvcs.yaml` on pve1): priority 2 "Backups OK: <steps> (N min)" or
  priority 4 "Backups failed: failed: <steps>; ok: <steps>". Exit is non-zero on any
  failure, so the unit shows failed for node_exporter's systemd collector too.
- **vm_watchdog.** It exits within ~15s of SIGTERM and only resets a guest after 60s of
  failed agent pings, so it wasn't really racing the shutdown. `After=pve-guests.service`
  now makes that ordering explicit: it stops before guests are shut down.
- **Gatus.** The maintenance window (Sunday 01:00, 2h) already matched; the comment now
  points at the timer.
- **Offsite (step 5).** Left out until 03 picks a target; it becomes one more step.

Tested by rendering (dispatcher/sudoers regenerate with `install_backup_orchestrator` and
`run_backups`), shellcheck, and a stubbed run under bash 5 covering: pve2 off, all OK
(wakes, runs everything, shuts down, exit 0); `backup_hass` fails (the rest still runs,
the hass timestamp is kept, exit 1); pve2 never wakes (only `start_pve2` runs, exit 1,
failure posted); pve2 already on (no shutdown). Not run on the real hosts.

Human:
1. Deploy, then `install_dispatcher` on pve2 (for `run_backups`), `install_vm_watchdog`
   on pve1 and pve2, and `install_backup_orchestrator` on pve1.
2. Delete the UI backup jobs on both hosts (Datacenter >> Backup) now, not in 02: pve1's
   also fires Sunday 01:00, and vzdump's node lock would run the two back to back and
   take a second snapshot.
3. `systemctl start backup_orchestrator` with pve2 off, then check the Acceptance items
   (fresh snapshots in PBS, pve2 off afterwards, the metric in VictoriaMetrics).
