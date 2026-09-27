# 02. Own the backup schedule from the repo, not the PVE UI

Status: ready-for-agent
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
