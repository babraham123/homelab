# 03. Copy the PBS datastore offsite after each run

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 1
Blocked by: 01

## Problem

One copy of every backup, on the same machine as most of the VMs it backs up. Losing pve2 loses
pve2's VMs and every backup of pve1.

## Change

PBS-native: a PBS 4 S3-compatible datastore (B2 or similar) as a push sync target for `backup1`.
Every chunk is already encrypted with pve1's client key, so the remote holds only ciphertext without
a second tool.

- **Where it runs:** a new step in `src/nodes/pve1/backup_orchestrator.sh.j2`, `step_offsite`, that
  calls a new pve2 dispatcher command the same way `step_prune` calls `prune`
  (`ssh autoadmin@pve2 offsite`). List it in `PBS_STEPS` after `upload` and `prune`, so the push
  carries this week's VM images, pve1's `files` and `pve1/vpnsvcs` host backups, and none of the
  snapshots prune just removed; and before `acme_transfer`, which reloads PBS's proxy.
- **pve2 stays up:** `sleep_pve2` runs only after every PBS step, so the push must finish inside the
  step (the pve2 script waits on the sync task's UPID, like `prune.sh`'s `pbs_task`).
- **Metric and summary:** being a step, it gets
  `homelab_backup_last_success_timestamp_seconds{job="offsite"}` and a place in the ntfy summary
  with no further wiring.
- **Remote retention and checks:** mirror local retention (sync with remove-vanished, or a prune job
  per namespace on the S3 datastore), and a monthly PBS verify job on the remote.
- Before choosing the provider, check whether PBS's S3 backend has left tech preview.

## Acceptance

- After a scheduled run, the remote contains the latest snapshots.
- Documented restore path from the *remote* copy with pve2 assumed dead (feeds issue 06).

## Notes

Human decision needed on the remote provider and monthly cost before an agent can finish this.

## Comments

- 2026-09-27: 01 landed. Add `step_offsite_copy` to `src/nodes/pve1/backup_orchestrator.sh.j2` and
  append `offsite_copy` to `STEPS` after `vzdump_pve2`: it then gets a
  `homelab_backup_last_success_timestamp_seconds{job="offsite_copy"}` series and a place in the ntfy
  summary with no further wiring. pve2 is powered off after the last step, so the copy must finish
  inside the step (or keep pve2 up until it does).

- 2026-10-04: Decision from the backup restructure: PBS-native. Use a PBS 4 S3-compatible datastore
  as a push sync target (B2 or similar); restic is out, since every chunk in `backup1` is already
  encrypted with pve1's client key, so the remote holds ciphertext without a second tool. The sync
  job runs as a step at the end of pve2's `backup.sh images`, before the orchestrator powers pve2
  off, and gets a `homelab_backup_last_success_timestamp_seconds` series through the `images_pve2`
  step. Still ready-for-human: provider, bucket, budget.

- 2026-10-17: The placements in both comments above are superseded. The orchestrator's steps are now
  `router_local`, `backup_<node>`, `upload`, `prune`, `acme_transfer`; pve2's `backup.sh` has no
  `images` subcommand and there is no `vzdump_pve2` or `images_pve2` step. A sync at the end of
  pve2's `backup.sh` would also run before pve1's `upload`, missing the `files` namespace and the
  vpnsvcs host backup. Change now places the push as its own PBS step after `upload` and `prune`.
