# 02. Own the backup schedule from the repo, not the PVE UI

Status: resolved
Type: task
Repo: homelab
Source: review finding 2
Blocked by: 01

## Problem

The vzdump schedule is click-configured in the PVE UI (`docs/guides/proxmox.md.j2:219-223`)
and is therefore not reproducible from the repo, and it runs independently of whether
pve2 is up.

## Change

- Disable the UI-created backup jobs on both PVE hosts (they move into the orchestrator).
- Make the orchestrator's timer the single schedule. Put cadence and retention in
  `vars.yml` (`backup.schedule`, `backup.keep_daily/weekly/monthly`) and template them
  into `backup_orchestrator.timer` and the PBS prune job (`proxmox-backup-manager prune-job
  update` can be driven from `commands.sh` on pve2, or keep prune/GC in PBS and document
  the values as the source of truth).
- Template the `vzdump` invocation flags (mode, compress, notes-template) into the
  orchestrator so they're reviewable.

## Acceptance

- `grep -r backup vars.yml` shows the schedule; no backup job remains in `/etc/pve/jobs.cfg`
  on either host.
- Changing `vars.yml` + `deploy_src.sh` + `install_backup_orchestrator` changes the
  actual cadence.

## Comments

- 2026-09-27: 01 landed. The schedule is `OnCalendar=Sun *-*-* 01:00:00` in
  `src/pve1/backup_orchestrator.timer` (not a .j2 yet), and the Gatus maintenance window
  in `src/gatus/config.yaml.j2` mirrors it, so template both from `backup.schedule`. The
  vzdump flags are `--storage pbs2 --mode snapshot` in `step_vzdump_pve1` and in
  `run_backups` (`src/pve2/commands.sh.j2`). 01 asked the human to delete the UI jobs
  already. PBS prune/GC schedules only fire while pve2 is up, and pve2 is now up only
  during the run, so drive prune/GC from `run_backups` or schedule them inside the window.

## Answer

Done with the backup restructure (2026-10-04), hardcoded rather than in `vars.yml` by
maintainer decision: the schedule is `OnCalendar=Sat *-*-* 02:00:00` in
`src/pve1/backup_orchestrator.timer` with the Gatus maintenance window to match;
retention is three PBS prune jobs that pve2's `prune.sh` creates or updates and runs as
the orchestrator's last step (after the upload), then garbage collection, so prune/GC
happen while pve2 is awake and count the run's own snapshots:
`images-pve1` and `images-pve2` (keep last 1, weekly 2, monthly 2; `host/vpnsvcs` sits
in `pve1` and takes the same) and `files` (last 1, weekly 3, monthly 6). The vzdump
calls are `pvesh create /nodes/<n>/vzdump --storage pbs2 --mode snapshot`. Human: delete
any PBS UI prune and GC job and confirm Datacenter >> Backup is empty on both hosts.
