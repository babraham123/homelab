# 11. Back up to PBS as a backup-only user, and decide on client-side encryption

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer answer to backup-and-dr/09 open question 1 (2026-09-27)

## Problem

pve1's `pbs2` storage authenticates to PBS as `root@pam`. That password sits in
`/etc/pve/priv/storage/pbs2.pw` on pve1, so anyone with root on pve1 is also root on
PBS (and on pve2, since PBS runs there). With it they can delete every backup, including
the offsite copy's source (03). A ransomware-style compromise of pve1 therefore takes the
backups with it.

It's also unknown whether the storage uses a client-side encryption key.

## Change

1. **Backup-only identity.** On PBS, create a dedicated user or API token for pve1
   (e.g. `pve1@pbs`, or a token `pve1@pbs!backup`) with the `DatastoreBackup` role on
   `/datastore/backup1/pve1` only.
   - That role can create backups and read or restore its own, but can't prune or
     delete.
   - Pruning and GC run as PBS-side jobs (backup-and-dr/02), not from pve1.
   - Check what backup-and-dr/01's orchestrator and 10's `proxmox-backup-client` run
     need, and grant nothing more.
2. **Switch the storage** on pve1 to the new identity
   (`pvesm set pbs2 --username ... --password ...`), and store the secret in
   `/root/secrets/pve1.yaml` (`src/pve1/secrets_template.yaml`).
3. **Document** the setup in `docs/guides/proxmox.md.j2` and step 3 of
   `docs/guides/pve1_recovery.md.j2`, replacing `USER@REALM`.

## Research: is client-side encryption needed?

Answer under `## Answer` before changing anything:

- **Current state:** does the storage already have a key? Check
  `ls /etc/pve/priv/storage/pbs2.enc` and the `encryption-key` line in `storage.cfg`.
- **What it protects:** PBS data at rest on pve2's disk, and above all the offsite copy
  (03), where the datastore leaves the house. The images contain `/root/secrets`,
  private CA keys and the SOPS files.
- **What it costs:**
  - Without the key, nothing can be restored, so it joins the escrow set (04) and the
    DR guide (09).
  - Confirm that PBS verify jobs still work, since they check the encrypted chunks'
    digests.
  - Dedup across VMs still works for chunks encrypted with the same key.
- **Alternatives:** encrypt only the offsite copy (the sync target or rclone crypt,
  per 03's design), keeping local restores key-free.
- **Recommendation:** key or no key, where it is escrowed, and how an existing
  unencrypted datastore migrates (new backups encrypted; old ones pruned out).

## Acceptance

- `pvesm status` on pve1 shows `pbs2` active under the new identity. A backup and a
  restore of a scratch VM both succeed.
- As that identity, `proxmox-backup-client snapshot forget` on a pve1 snapshot is
  refused.
- `## Answer` records the encryption decision, and 04's escrow list and 09's guide match
  it.

## Comments

## Answer

**Encryption: yes, one client key, held on pve1.** Decided in the backup restructure
(2026-10-04): `/root/secrets/pbs_client.key` (`proxmox-backup-client key create --kdf
none`) is used by the `pbs2` PVE storage on pve1 (`--encryption-key`) and by the host
backup upload, so images and files share one key and dedup across them; pve2's storage
gets a copy so its images are ciphertext too. Verify jobs work on encrypted chunks
(digests are of the ciphertext). The key joins the escrow set (04), and the copy of it
inside PBS is useless without itself, so escrow is a hard prerequisite. Old unencrypted
snapshots stay restorable and prune out over time. Encrypting only an offsite copy was
rejected: the datastore sits on the same box as most of the VMs.

**Identity:** user `pve1@pbs`, token `pve1@pbs!backup`, `DatastoreBackup` on
`/datastore/backup1/pve1` and `/datastore/backup1/files` (the new namespace for the
host backups; retention is per namespace). The secret is `pbs2_backup_token` in
`/root/secrets/pve1.yaml` (`src/pve1/secrets_template.yaml`); the orchestrator reads
it with sops for `PBS_PASSWORD`. pve2's storage stays `root@pam`: PBS is local to it.

Code side done: `secrets_template.yaml`, the orchestrator's `step_upload`,
`docs/guides/proxmox.md#backups` and `pve1_recovery.md` step 3. Human side (the apply
guide, `notes/apply-since-5a50097.md`): create the `files` namespace, the user, token
and ACLs on PBS, the key
on pve1, enter the token in `pve1.yaml`, `pvesm set pbs2` on both hosts, then the
acceptance checks: `pvesm status`, a scratch restore, and `proxmox-backup-client
snapshot forget` refused as the token.
