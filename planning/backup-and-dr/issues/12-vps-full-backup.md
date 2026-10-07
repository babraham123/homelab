# 12. Full backup of the VPS via dispatcher

Status: resolved
Type: task
Repo: homelab
Source: maintainer request 2026-09-27

## Problem

vpn is the only Debian node that isn't a Proxmox VM, so vzdump never backs it up.
Losing it loses the Headscale DB and noise key (every tailnet node re-registers), the
SSH host keys and cert, the ufw/iptables rules and the HAProxy setup.

## Change

- `src/vpn/backup_full.sh`, run by the `backup_full` dispatcher command (dispatcher,
  sudoers and OliveTin via `src/nodes.yml`): `sqlite3 .backup` of the Headscale DB, then a zstd tar of `/`
  (`--one-file-system`, no apt caches or tmp) with the snapshot in place of the live DB
  files. Writes `/var/opt/backups/full/vpn-full-<ts>.tar.zst`, owned by autoadmin (mode
  400) so pve1 can `scp` it off, keeps the newest 2, and lists the archive back to check
  it decompresses and holds exactly one DB.
- `sqlite3` installed by `install_svcs.sh headscale`; `zstd` added to the Debian basics.
- Restore (single file and whole VPS via Linode Rescue Mode) in `docs/guides/vpn.md.j2`.

## Acceptance

- `ssh autoadmin@vpn backup_full` leaves an archive in `/var/opt/backups/full/`, and
  `scp` as autoadmin copies it to pve1.
- The Headscale DB extracted from it opens with `sqlite3 db.sqlite 'PRAGMA integrity_check'`.

## Comments

2026-09-27: Implemented as above. Pulling the archive on a schedule and sending it to PBS
is 10's orchestrator step; 10's vpn `backup_paths` can be just this archive.
Human: redeploy vpn (`install_headscale` for sqlite3, `apt install zstd`,
`install_dispatcher`), run `backup_full`, and check Acceptance.
Open: the archive is plaintext and readable with the autoadmin key; encrypting it to pve1's age key waits on 04 (TODO in `backup_full.sh`).

- 2026-10-04: Superseded by the backup restructure: `backup_full.sh` is replaced by
`src/vpnsvcs/backup.sh.j2` (`backup`), which stages the Headscale DB snapshot and
the state and config a fresh Debian can't regenerate instead of the whole root
filesystem; the OS is rebuilt from the guide. The plaintext-archive TODO is moot: the
stage is pulled by pve1 and encrypted on upload, as its own PBS group `host/vpnsvcs` with the image retention. `docs/guides/vpnsvcs.md#backup-and-restore`
has the new restore path.
