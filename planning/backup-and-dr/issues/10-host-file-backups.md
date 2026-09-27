# 10. Back up the important files on every host, not only the VM images

Status: ready-for-agent
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
- **vpn (VPS):** Headscale's database and noise private key, `/etc/ssh` host keys and
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
