# 10. Back up the important files on every host, not only the VM images

Status: resolved
Type: task
Blocked by: 01
Repo: homelab
Source: maintainer request 2026-09-27 (after 09)

## Problem

VM backups (vzdump → PBS) cover secsvcs, homesvcs, websvcs and the router VM's disk, but
not the hosts that aren't VMs on pve1, or the files outside a VM image:

- **pve1 host:** `/root/ca`, `/root/ssh`, `/root/secrets`, `/root/.ssh`, `/etc/pve`,
  `/etc/network/interfaces`, `/root/homelab-rendered`. 09's inventory lists them; today
  nothing copies them anywhere except the planned escrow (04).
- **pve2 host and PBS:** `/etc/pve`, `/etc/proxmox-backup` (datastore config, users,
  `encryption-key`), network config.
- **vpnsvcs (VPS):** Headscale's database and noise private key, `/etc/ssh` host keys and
  cert, ufw rules. Losing the Headscale DB re-registers every tailnet node.
- **router:** pfSense `config.xml`. ACB covers it only if the device key is recoverable
  (09's TODO); a local copy removes that dependency.
- **devtop, gaming:** whatever 09-style review finds worth keeping (SSH host keys/certs,
  Sunshine config).

## Change

1. **Inventory.** For each node in `src/nodes.yml`, list the paths worth keeping, with a
   one-line why per path. Derive them from `src/<node>/install_svcs.sh`, the guides, and
   09's tables. Declare them in `nodes.yml` (e.g. `backup_paths:`), so the list lives
   next to the rest of the node's facts.
2. **Per-host command.** A `backup_files` dispatcher command, generated from
   `backup_paths`, that writes `/var/opt/backups/files/<node>-files-<ts>.tar.zst`
   (mode 600, keep last N), following the pattern of `pg_dumpall` (07) and `backup_hass`
   (08). pfSense needs its own path (`scpsoc` of `/cf/conf/config.xml`, as
   `ssh_cert_gen.sh` does for the router).
3. **Orchestrator pull.** 01's orchestrator runs `backup_files` on each reachable host
   and `scp`s the archive to `/root/backups/files/` on pve1. Hosts whose disks are
   already in a VM backup still get pulled, so a single file restores without a VM
   restore.
4. **Into PBS.** One `proxmox-backup-client backup files.pxar:/root/backups` run per
   orchestrator pass sends pve1's collection (and pve1's own host paths) to `pbs2`, and
   through 03 offsite. Secrets in the archives stay encrypted at rest only if the PBS
   storage has an encryption key; if it doesn't, `age`-encrypt the archives to pve1's
   `age.pub` before upload (as 05 does for the repo).
5. **Docs.** Add the per-host lists to 09's guide as the restore source, and a
   single-file restore example to `docs/maintenance.md`.

## Acceptance

- After one orchestrator run, PBS holds a `host/pve1` snapshot containing an archive per
  reachable host.
- A named file (e.g. the VPS Headscale DB) restores from PBS to a scratch path without
  touching any VM.
- An unreachable host (pve2 asleep, VPS down) is reported by the orchestrator's summary
  and doesn't abort the run.

## Comments

2026-09-27: vpnsvcs is covered by 12's `backup_full` (whole root, consistent Headscale DB). For vpnsvcs, step 3 pulls `/var/opt/backups/full/vpnsvcs-full-*.tar.zst` after running it, instead of a `backup_files` built from `backup_paths`.

- 2026-09-27: 01 landed. Steps are `step_<name>` functions listed in `STEPS` in
  `src/pve1/backup_orchestrator.sh.j2`. A failing step is recorded and the run continues
  (only `wake_pve2` aborts), which already covers "unreachable host doesn't abort". Put
  the pulls before `vzdump_pve1` so pve1's collection lands before the PBS upload, and
  give each host its own step (e.g. `files_<node>`) so each gets its own
  `homelab_backup_last_success_timestamp_seconds{job=...}` series.

## Answer

Done with the backup restructure (2026-10-04), in a different shape from the ticket:

- No `backup_paths` in `nodes.yml`: each node has a hand-written `src/<node>/backup.sh`
  (pve1, pve2, secsvcs, homesvcs, websvcs, vpnsvcs) that runs its application hooks
  (`pg_dumpall`, HA native backup, Headscale `sqlite3 .backup`) into `dumps/<name>/` and
  mirrors explicit config paths and small volumes into `files/` under
  `/var/opt/backups/` with `rsync --relative` (`src/debian/backup_lib.sh`). Each script
  names what it skips and why. On pve1 and pve2 the same script goes on to the VM images.
  The old `pg_dumpall`, `backup_hass`, `backup_full` and `run_backups` commands are gone;
  `backup` is the one dispatcher command per node, no arguments.
- No tarballs and no `age`: plain trees dedup in PBS, and the upload is encrypted with
  pve1's client key (11).
- The orchestrator (`src/pve1/backup_orchestrator.sh.j2`) runs `backup_<node>` steps
  (ssh `backup`, rsync `files/` into `/root/backups/<node>/files/`, move `dumps/` there,
  keep only the newest dump of each kind), then `upload`: `host/vpnsvcs` into namespace
  `pve1` and `host/pve1` (the rest of `/root/backups`) into namespace `files`. After a
  successful upload the dumps are deleted from pve1; the node keeps only its newest one
  in case a pull never came, so a failed upload leaves exactly one behind.
- Router: not pulled; its `config.xml` is inside the router VM image and in ACB.
  devtop/gaming: images only.
- Docs: `docs/services.md#storage-and-backups`, `docs/guides/restore.md`, and the
  `pve1_recovery.md` table.
