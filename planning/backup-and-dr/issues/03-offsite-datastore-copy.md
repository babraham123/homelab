# 03. Copy the PBS datastore offsite after each run

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 1
Blocked by: 01

## Problem

One copy of every backup, on the same machine as most of the VMs it backs up. Losing
pve2 loses pve2's VMs and every backup of pve1.

## Change

Pick one, then implement as the orchestrator's final step:

- **restic** (as requested): `restic -r <remote> backup /path/to/backup1` from pve2
  (new `commands.sh offsite_copy` behind the dispatcher), repo password from the
  SOPS/AGE pipeline, target = B2/S3/rsync.net/a friend's box. PBS chunks are already
  deduped, so restic dedup adds little, but it gives encryption-at-rest offsite and a
  second, independent tool for restore.
- **PBS-native alternative worth a look:** PBS 4 (trixie, which you're on) has an
  S3-compatible object-store datastore backend and sync jobs can *push* to it. Less
  tooling, restore stays inside PBS. Check whether it left tech preview before choosing.

Either way: prune policy on the remote, a monthly `restic check --read-data-subset`
(or PBS verify job), and the run's success timestamp fed into the same textfile metric
as issue 01.

## Acceptance

- After a scheduled run, the remote contains the latest snapshots.
- Documented restore path from the *remote* copy with pve2 assumed dead (feeds issue 06).

## Notes

Human decision needed on the remote provider and monthly cost before an agent can
finish this.

## Comments

- 2026-09-27: 01 landed. Add `step_offsite_copy` to `src/pve1/backup_orchestrator.sh.j2`
  and append `offsite_copy` to `STEPS` after `vzdump_pve2`: it then gets a
  `homelab_backup_last_success_timestamp_seconds{job="offsite_copy"}` series and a
  place in the ntfy summary with no further wiring. pve2 is powered off after the last
  step, so the copy must finish inside the step (or keep pve2 up until it does).

- 2026-10-04: Decision from the backup restructure: PBS-native. Use a PBS 4 S3-compatible datastore
as a push sync target (B2 or similar); restic is out, since every chunk in `backup1` is
already encrypted with pve1's client key, so the remote holds ciphertext without a second
tool. The sync job runs as a step at the end of pve2's `backup.sh images`, before the
orchestrator powers pve2 off, and gets a `homelab_backup_last_success_timestamp_seconds`
series through the `images_pve2` step. Still ready-for-human: provider, bucket, budget.
