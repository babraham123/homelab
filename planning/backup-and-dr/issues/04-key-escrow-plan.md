# 04. Escrow plan for the AGE key, CAs and other trust roots

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 3

## Problem

`docs/security.md` names pve1's AGE key as the single point of failure and stops there. Losing
`/root/secrets/age.txt` makes every `secrets.yaml.age` on every host unrecoverable. The private CA,
SSH CA and `vars.yml` have the same exposure.

## Change

Write `docs/guides/escrow.md` and implement it:

1. **Medium:** an encrypted USB stick (LUKS on Linux; note macOS can't open LUKS without extra
   tooling, so also consider a `age -p` (passphrase) encrypted tarball that any machine can open).
   Two sticks, two locations (home + off-site).
2. **Contents:** the rows marked "Escrow" in `docs/guides/pve1_recovery.md.j2` (the canonical
   list): `/root/secrets/age.txt`, `age.pub`, `pbs_client.key`, `pve1.yaml` (holds
   `pbs2_backup_token`) and the per-host `*.yaml.age`; the root and intermediate CA keys, certs,
   `index.txt`, `serial`, `crlnumber` and CRLs, and the service keys under `/root/ca/`; the SSH user
   and host CA keys under `/root/ssh/`; `vars.yml`. Plus Vaultwarden's plaintext admin token (the
   secrets file holds only its hash) and a password-protected Bitwarden JSON export. Not escrowed,
   per that guide: `acme.json` lives on secsvcs, homesvcs and websvcs and is covered by their PBS
   VM backups; `/root/acme/`, host recipient keys and SSH host certs are regenerated; pfSense
   `config.xml` and `/etc/pve` are covered by PBS backups (and Auto Config Backup).
3. **Second AGE recipient.** Generate an offline AGE key kept only on the sticks and add its public
   key as a recipient in `secret_update.sh` (`-R /root/secrets/age_escrow.pub`) so a future
   re-encryption of the secret files is possible without pve1.
4. **Refresh cadence** (annual, or on any CA/secret rotation) and a checklist in
   `docs/maintenance.md`.
5. A `commands.sh export_escrow` on pve1 that assembles the bundle into an `age -p` encrypted
   tarball in one step, so the refresh is a single command + passphrase.

## Acceptance

- `docs/guides/escrow.md` exists and `docs/maintenance.md` links to it.
- A dry run: decrypt one `secrets.yaml.age` using only the escrow key on a laptop.

## Comments

- 2026-10-04: Now a hard prerequisite for the backup restructure, not a nice-to-have: every image
  and host backup pve1 sends to PBS is encrypted with `/root/secrets/pbs_client.key`, and the copy
  of that key inside PBS is encrypted with itself. The escrow set gains `pbs_client.key` and the
  `pbs2_backup_token` value from `pve1.yaml` (the identity that can read the backups).
  `docs/guides/pve1_recovery.md` and `docs/guides/restore.md` describe the restore that depends on
  them. Unblocked: 09 is resolved.
- 2026-10-12 (vaultwarden/01): the escrow set gains Vaultwarden's plaintext admin token (SOPS holds
  only its hash) and a periodic password-protected Bitwarden JSON export, so the passwords needed to
  rebuild the homelab don't live only in the homelab.
- 2026-10-17: Change item 2 now follows `docs/guides/pve1_recovery.md.j2`'s Escrow rows and folds in
  the two additions above. Dropped from the list: `acme.json` (on the VMs, covered by PBS),
  `/root/acme/`, host recipient keys and the gaming VM's SSH cert material (regenerated), pfSense
  `config.xml` and the `/etc/pve` tarball (PBS backups).
- 2026-10-25: SOPS is gone (ADR 0004): pve1's per-host source is `/root/secrets/<host>.yaml.age`, the
  same file each VM has, so the escrow set lists the `.yaml.age` files instead of `.yaml`.
