# Backups and disaster recovery

Today PBS runs on pve2, stores backups on pve2's own disk, and its schedule only fires
when pve2 happens to be powered on. There is no offsite copy, no key escrow, no restore
test, and no DR runbook. This effort makes pve1 the backup orchestrator, adds
application-consistent dumps for Postgres and Home Assistant, copies the datastore
offsite, and documents recovery.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-backup-orchestrator-on-pve1.md) | Backup orchestrator on pve1 that wakes pve2 | `ready-for-agent` | task |
| [02](issues/02-backup-schedule-in-code.md) | Own the backup schedule from the repo, not the PVE UI | `ready-for-agent` | task |
| [03](issues/03-offsite-datastore-copy.md) | Copy the PBS datastore offsite after each run | `ready-for-human` | task |
| [04](issues/04-key-escrow-plan.md) | Escrow plan for the AGE key, CAs and other trust roots | `ready-for-human` | task |
| [05](issues/05-repo-backup-on-deploy.md) | Back up the repo (incl. vars.yml) to pve1 on every deploy | `ready-for-agent` | task |
| [06](issues/06-vm-restore-runbook.md) | Restore instructions for VMs on pve1 and pve2, and a quarterly test | `ready-for-agent` | task |
| [07](issues/07-pg-dumpall-dispatcher.md) | pg_dumpall via dispatcher, triggered by the orchestrator | `resolved` | task |
| [08](issues/08-home-assistant-backup.md) | Home Assistant native backup via dispatcher, triggered by the orchestrator | `resolved` | task |
| [09](issues/09-pve1-disaster-recovery-guide.md) | pve1 disaster recovery guide with the complete escrow/backup file list | `resolved` | task |
| [10](issues/10-host-file-backups.md) | Back up the important files on every host, not only the VM images | `ready-for-agent` | task |
| [11](issues/11-pbs-backup-user-and-encryption.md) | Back up to PBS as a backup-only user, and decide on client-side encryption | `ready-for-agent` | task |
| [12](issues/12-vps-full-backup.md) | Full backup of the VPS via dispatcher | `resolved` | task |
