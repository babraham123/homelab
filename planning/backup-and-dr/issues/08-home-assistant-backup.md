# 08. Home Assistant native backup via dispatcher, triggered by the orchestrator

Status: resolved
Type: task
Repo: homelab
Source: review finding 7 (user items 7 and 9)

## Problem

Home Assistant has no native backup; only the VM image. A VM snapshot doesn't help when
the HA config or an HA upgrade *is* the problem, and HA's own `.tar` backups restore
across versions.

## Change

- Enable the HA backup integration in `src/home_assistant/configuration.yaml.j2`
  (`backup:`), and create a long-lived access token stored as `hass_backup_token` in the
  homesvcs secrets.
- `src/homesvcs/commands.sh backup_hass`: call `POST /api/services/backup/create`
  (or `ha backups new` is Supervisor-only; container installs use the API), wait for
  completion, copy the resulting archive out of the `hassconfig` volume to
  `/var/opt/backups/hass/`, keep last 8.
- Add `backup_hass)` to `src/homesvcs/dispatcher.sh`.
- Orchestrator (issue 01) calls it before `vzdump homesvcs`; the archive then rides
  inside the VM backup to pbs2 and offsite.

## Acceptance

- `ssh autoadmin@homesvcs backup_hass` produces an archive HA can restore from
  Settings → System → Backups on a scratch instance.

## Comments

2026-09-27: Added `backup_hass` (commands.sh + dispatcher/sudoers): blocking REST `backup.create`, copies the new `Custom_backup_*.tar` to `/var/opt/backups/hass/` (keep 8), keeps only the newest in `/config/backups`; `backup:` listed in config (core loads it anyway). Recorder DB is in `hassdb`, outside `/config`, so the archive has no history.
Human: create an admin long-lived token → `hass_backup_token` in homesvcs secrets, redeploy, run `ssh autoadmin@homesvcs backup_hass`, and restore the archive on a scratch instance to meet Acceptance.
