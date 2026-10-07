# 05. Back up the repo (incl. vars.yml) to pve1 on every deploy

Status: resolved
Type: task
Repo: homelab
Source: review finding 4

## Problem

`tools/backup_src.sh` writes an **unencrypted** tarball containing `vars.yml` and `.git`
to an arbitrary path, on no schedule. `vars.yml` is the only un-versioned input to the
entire render pipeline.

## Change

- In `tools/deploy_src.sh`, after a successful render: `tar` the working tree
  (`git ls-files` + `vars.yml`; `planning/` is tracked, so it is included), encrypt with
  `age -R <pve1 age.pub>` (the public key is safe to commit as `age.pub` or keep in
  `vars.yml`), and `scp` to `manualadmin@pve1:~/homelab-src-<date>.tar.gz.age`; a
  `commands.sh archive_repo_backup` on pve1 moves it to `/root/backups/repo/` and keeps
  the last N.
- Delete `tools/backup_src.sh` or reduce it to the encrypted variant.
- `/root/backups/repo/` is covered by the pve1 VM/host backup and by the escrow bundle
  (issue 04).

## Acceptance

- After `tools/deploy_src.sh`, a new `.tar.gz.age` exists on pve1 and can be decrypted
  with `age.txt`.
- No plaintext copy of `vars.yml` is produced anywhere in the process.

## Comments

## Answer

Done with the backup restructure (2026-10-04), with one change from the ticket: no
`age` on the archive. `tools/deploy_src.sh` tars `git ls-files` plus `vars.yml` and
pipes it over ssh to the new `archive_repo` dispatcher command on pve1
(`src/pve1/commands.sh.j2`), which writes `/root/backups/repo/homelab-<ts>.tar.gz`
(root, 0600, newest 3 kept). ssh encrypts it in flight, pve1 already
holds every secret, and the weekly host backup carries `/root/backups` to PBS encrypted
with the client key, so an `age` layer would only have hurt dedup. `tools/backup_src.sh`
is deleted.
