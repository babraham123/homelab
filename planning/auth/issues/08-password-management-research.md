# 08. Research: manage SSH, sudo, CA and recovery passwords better than offline notes

Status: ready-for-agent
Type: research
Repo: homelab
Source: maintainer request 2026-09-27 (backup-and-dr/09 open questions 2 and 5)

## Problem

Every human-held secret is stored offline and nowhere else:

- passphrases of `ca.key.pem`, `intermediate.key.pem` and `ca_ssh_key` on pve1;
- `manualadmin`/root sudo passwords on each host;
- pfSense's ACB device key and encryption password;
- Proxmox, PBS and pfSense web admin passwords.

Consequences:

- Recovery (09's guide) depends on a physical copy being current and at hand.
- `docs/debugging.md#remote-sudo-non-interactively` pipes `<host>_root_pswd` from
  `/root/secrets/pve1.yaml`, but those keys aren't in `src/pve1/secrets_template.yaml`
  and, per the maintainer, the passwords aren't in SOPS at all. The documented recipe
  doesn't work.

## Questions to answer

1. **Where should these secrets live?** Evaluate:
   - self-hosted Vaultwarden (vaultwarden/01), including the DR bootstrap problem: it
     runs on secsvcs, which pve1's recovery must rebuild first;
   - a hosted password manager (Bitwarden, 1Password);
   - a KeePassXC database, escrowed per backup-and-dr/04;
   - a SOPS/age file in the repo or on pve1, with the age identity on a hardware key
     (`age-plugin-yubikey`).

   Compare them on:
   - availability when the homelab is down;
   - blast radius if the store leaks;
   - how it fits 04's escrow;
   - day-to-day friction.
2. **Can the passwords go away instead?**
   - **sudo:** SSH-certificate or agent-based sudo auth (`pam_ssh_agent_auth`, or
     `pam_rssh`), so sudo trusts the same SSH CA that already signs logins.
   - **Root and `manualadmin` passwords:** can they be locked, with console-only break
     glass?
   - **CA passphrases:** can they be replaced by hardware-backed keys (YubiKey PIV for
     the SSH CA, `ssh-keygen -t ed25519-sk`)?
   - **Blockers:** what breaks in the current scripts (`ssh_cert_gen.sh` first-run root
     password prompts, the debugging recipe)?
3. **Which secrets should stay offline-only?** Some, like the root CA passphrase, may be
   better off paper-only by design. Say which and why.

## Deliverable

Resolve under `## Answer`:
- a recommendation;
- an options table;
- per-secret placement: secret → store → who and what can read it → how it's recovered;
- follow-up tasks. At minimum, fix or remove the `docs/debugging.md` recipe, and update
  backup-and-dr/04's escrow list and 09's guide TODOs.

## Comments
