# 05. Back up the repo (incl. vars.yml) to pve1 on every deploy

Status: ready-for-agent
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
