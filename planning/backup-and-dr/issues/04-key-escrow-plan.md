# 04. Escrow plan for the AGE key, CAs and other trust roots

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 3

## Problem

`docs/security.md` names pve1's AGE key as the single point of failure and stops there.
Losing `/root/secrets/age.txt` makes every `secrets.yaml.age` on every host
unrecoverable. The private CA, SSH CA and `vars.yml` have the same exposure.

## Change

Write `docs/guides/escrow.md` and implement it:

1. **Medium:** an encrypted USB stick (LUKS on Linux; note macOS can't open LUKS
   without extra tooling, so also consider a `age -p` (passphrase) encrypted tarball
   that any machine can open). Two sticks, two locations (home + off-site).
2. **Contents** (the canonical list is issue 09):
   `/root/secrets/age.txt`, `age.pub`, `/root/secrets/*.yaml` (SOPS), `*_id_ed25519.pub`;
   `/root/ca/` (root + intermediate keys, serials, CRLs); `/root/ssh/` (SSH CA key);
   `/root/acme/`; `/etc/opt/traefik/certificates/acme.json`; `vars.yml`; the
   Windows gaming VM's SSH cert material; pfSense config XML; `/etc/pve` tarball.
3. **Second AGE recipient.** Generate an offline AGE key kept only on the sticks and add
   its public key as a recipient in `secret_update.sh` (`-R /root/secrets/age_escrow.pub`)
   so a future re-encryption of the secret files is possible without pve1.
4. **Refresh cadence** (quarterly, or on any CA/secret rotation) and a checklist in
   `docs/maintenance.md`.
5. A `commands.sh export_escrow` on pve1 that assembles the bundle into an `age -p`
   encrypted tarball in one step, so the refresh is a single command + passphrase.

## Acceptance

- `docs/guides/escrow.md` exists and `docs/maintenance.md` links to it.
- A dry run: decrypt one `secrets.yaml.age` using only the escrow key on a laptop.

## Comments

- 2026-10-04: Now a hard prerequisite for the backup restructure, not a nice-to-have: every image
and host backup pve1 sends to PBS is encrypted with `/root/secrets/pbs_client.key`, and
the copy of that key inside PBS is encrypted with itself. The escrow set gains
`pbs_client.key` and the `pbs2_backup_token` value from `pve1.yaml` (the identity that
can read the backups). `docs/guides/pve1_recovery.md` and `docs/guides/restore.md`
describe the restore that depends on them. Unblocked: 09 is resolved.
