# 08. Research: manage SSH, sudo, CA and recovery passwords better than offline notes

Status: resolved Type: research Repo: homelab Source: maintainer request 2026-09-27
(backup-and-dr/09 open questions 2 and 5)

## Problem

Every human-held secret is stored offline and nowhere else:

- passphrases of `ca.key.pem`, `intermediate.key.pem` and `ca_ssh_key` on pve1;
- `manualadmin`/root sudo passwords on each host;
- pfSense's ACB device key and encryption password;
- Proxmox, PBS and pfSense web admin passwords.

Consequences:

- Recovery (09's guide) depends on a physical copy being current and at hand.
- `docs/debugging.md#remote-sudo-non-interactively` pipes `<host>_root_pswd` from
  `/root/secrets/pve1.yaml`, but those keys aren't in `src/nodes/pve1/secrets_template.yaml` and,
  per the maintainer, the passwords aren't in SOPS at all. The documented recipe doesn't work.

## Questions to answer

1. **Where should these secrets live?** Evaluate:
   - self-hosted Vaultwarden (vaultwarden/01), including the DR bootstrap problem: it runs on
     secsvcs, which pve1's recovery must rebuild first;
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
   - **sudo:** SSH-certificate or agent-based sudo auth (`pam_ssh_agent_auth`, or `pam_rssh`), so
     sudo trusts the same SSH CA that already signs logins.
   - **Root and `manualadmin` passwords:** can they be locked, with console-only break glass?
   - **CA passphrases:** can they be replaced by hardware-backed keys (YubiKey PIV for the SSH CA,
     `ssh-keygen -t ed25519-sk`)?
   - **Blockers:** what breaks in the current scripts (`ssh_cert_gen.sh` first-run root password
     prompts, the debugging recipe)?
3. **Which secrets should stay offline-only?** Some, like the root CA passphrase, may be better off
   paper-only by design. Say which and why.

## Deliverable

Resolve under `## Answer`:

- a recommendation;
- an options table;
- per-secret placement: secret → store → who and what can read it → how it's recovered;
- follow-up tasks. At minimum, fix or remove the `docs/debugging.md` recipe, and update
  backup-and-dr/04's escrow list and 09's guide TODOs.

## Answer

Full research with sources: [08-research-notes.md](08-research-notes.md). Summary follows.

### Recommendation

**Vaultwarden is the one store for human passwords. The rarely used trust roots and a short
break-glass file stay in the offline escrow bundle. Most passwords are removed rather than moved.**

- **sudo passwords go away.** `manualadmin ALL=(ALL) NOPASSWD: ALL` on every Debian node, gated by
  a FIDO `ed25519-sk` workstation key signed with `-O verify-required` (PIN plus touch per login).
  pve1's root certificate loses the `manualadmin` principal; `secret_update.sh` moves to a
  dispatcher `install_secrets` command.
- **Root and manualadmin locked** on every Debian node (`passwd -l`). Key and certificate logins
  keep working under Debian's `UsePAM yes`. Break glass: `qm guest exec`, or the console with
  `SYSTEMD_SULOGIN_FORCE=1`.
- **Proxmox `root@pam` stays**: long random password plus TFA, in Vaultwarden and `breakglass.txt`.
  Locking it would kill web login; some settings are hard-coded root-only.
- **SSH user CA moves to two FIDO keys**, one `ed25519-sk` CA key per YubiKey, both public keys in
  `ca_ssh_key.pub`. No passphrase and no key backup needed; losing one key means deleting a line.
- **Root X.509 CA goes offline**: key on the escrow sticks only, removed from pve1 and PBS,
  passphrase on paper kept apart. Intermediate CA keeps its passphrase (in Vaultwarden); PIV
  migration not worth a re-key yet.
- **Agent-based sudo is rejected.** `pam_ssh_agent_auth` is orphaned in Debian and `pam_rssh`
  unpackaged; neither honours SSH certificates or a CA, and both need agent forwarding to every host.
- **Hosted Bitwarden / 1Password rejected**: they buy availability the escrow already provides and
  break the no-cloud goal. **KeePassXC and SOPS/age+YubiKey rejected** for human passwords: a
  second store and no autofill. SOPS ≥3.10 does support YubiKey identities, which suits 04's escrow
  identity.

### Options

| Store | Available when homelab is down | Blast radius on leak | Fit with 04 escrow | Friction |
| --- | --- | --- | --- | --- |
| Vaultwarden (secsvcs) | Locked clients unlock offline read-only; logged-out clients can't log in; worst case the escrowed export | Ciphertext under master password; lives on a host it helps recover | Export + admin token already escrowed | Lowest, already deployed |
| Hosted Bitwarden | Best | Same model, plus third-party target | Same export | Same clients |
| 1Password | Cloud + offline apps | Secret Key + password | 1PUX export is plaintext; Emergency Kit is paper | Low, ~$36-48/yr |
| KeePassXC escrowed | Full | KDBX4 + YubiKey HMAC | The `.kdbx` is the artifact | High: second store, no FIDO2 |
| SOPS/age + YubiKey | Full | Non-extractable PIV key; second recipient needed | Native | High for humans: no autofill |

### Per-secret placement

| Secret | Store | Readable by | Recovery |
| --- | --- | --- | --- |
| Root CA key + passphrase | Escrow sticks (key); paper (passphrase). Removed from pve1/PBS | Maintainer with both | "Only the private CA is lost" path |
| Intermediate CA passphrase | Vaultwarden; escrow export | Maintainer; pve1 root while signing | Re-key with root |
| SSH user CA | Two YubiKeys (sk); `.pub` on pve1 | YubiKey holder + PIN | Drop a lost key's line |
| SSH host CA | pve1 `/root/ssh` as today | pve1 root | As today |
| manualadmin / Debian root / autoadmin passwords | None: locked | — | Console, `qm guest exec` |
| pve1, pve2 `root@pam` (PBS = pve2) | Vaultwarden; `breakglass.txt`; TFA | Maintainer | Physical console, rescue boot |
| pve2 `pbs2` storage credential | PBS token, replacing root's password | pve2 root | New token |
| pfSense admin | Vaultwarden; `breakglass.txt` | Maintainer | Console option 3 via pve1 noVNC |
| ACB device key + password | Vaultwarden; `breakglass.txt` | Maintainer | Password lost: old ACB backups gone |
| gaming admin | Vaultwarden | Maintainer | pve2 console |
| Linode account + 2FA | Vaultwarden; `breakglass.txt` | Maintainer | Linode recovery |
| Vaultwarden master password | Memory + paper | Maintainer | None by design |
| Escrow bundle / identity passphrases | Paper only | Maintainer | Re-cut bundle from pve1 |

### Offline-only, and why

Root CA key and passphrase (used once a decade, root compromise forces a new trust anchor
everywhere); escrow passphrases and Vaultwarden master password (the store can't hold its own key);
the two SSH-CA YubiKeys; and `breakglass.txt` with the secrets needed before secsvcs is back.

### Findings beyond the ticket

- The `docs/debugging.md` recipe was already rewritten in `b02f3a8`; it works but still needs a
  typed password. The ticket's premise is stale, the root cause (no store) stands.
- First-run `ssh_cert_gen.sh` is broken: `install_ssh_ca` is `pve1_file_transfer: true`, so a host
  that doesn't yet trust the CA falls back to a password login and `require_pve1` rejects it.
  `pve1.md.j2:48-49` and `pve1_recovery.md.j2:343` are wrong. Blocks 09's "Nothing escrowed" path.
- `self_signed_cert_gen.sh.j2:28` passes the intermediate passphrase as `-passin pass:`, visible
  in `ps`.
- pve2's `pbs2` storage stores root's password in `/etc/pve/priv/storage/pbs2.pw`.
- Prompts labelled "root password" actually want manualadmin's sudo password.
- `secret_update.sh:21` comment "SOPS doesn't support SSH keys" is stale since SOPS 3.10.

### Follow-up tasks

1. Debugging recipe: replace with "sudo is passwordless for manualadmin" once NOPASSWD lands.
2. Hardware login key: Homebrew openssh on the Mac, `ssh-keygen -t ed25519-sk -O verify-required`;
   sign in `ssh_cert_gen.sh.j2:84-87` with `-O verify-required -n manualadmin,autoadmin,admin`.
3. `ssh_cert_gen.sh.j2:71` → `-n autoadmin,admin`; add dispatcher `install_secrets`; rewrite
   `secret_update.sh:25-37`.
4. NOPASSWD sudoers; lock passwords; drop prompts from `upload_src.sh:45` and
   `secret_update.sh:27`; update `CONTEXT.md` and `docs/security.md:211-212`.
5. Bootstrap fix (independent): document or script the first-run `ca_ssh_key.pub` install; fix
   `pve1.md.j2:48-49` and `pve1_recovery.md.j2:343`.
6. SSH user CA on two FIDO keys: `pve1.md.j2:34-37`, two-line `ca_ssh_key.pub`, sign with
   whichever handle file is present, add YubiKeys to 09's inventory.
7. Root CA offline: move `ca.key.pem` to escrow sticks, exclude from pve1 `backup.sh`, update
   `pve1_recovery.md.j2:35` and the "Only the private CA is lost" section.
8. `self_signed_cert_gen.sh.j2`: `-passin fd:3`.
9. pve2 PBS credential → `pve2@pbs!backup` token (fits backup-and-dr/11).
10. TFA on `root@pam` for pve1, pve2, PBS; document in `proxmox.md.j2`.
11. pfSense SSH "Public Key Only" and `admin` principal, replacing prompts in `upload_src.sh:20-21`
    and `ssh_cert_gen.sh.j2:48`; test the same for gaming (`upload_src.sh:27-28`).
12. backup-and-dr/04 escrow list: add root CA key (only copy) and `breakglass.txt`; note the escrow
    age identity must be X25519 wrapped with `age -p`; list paper items; drop CA passphrase notes.
13. backup-and-dr/09 and `pve1_recovery.md.j2`: lines 42, 61, 267-268; drop the `<host>_root_pswd`
    TODO (those keys must not go into SOPS).
14. Fix the stale SOPS comment in `secret_update.sh:21`.

Unverified: Windows mapping of an `admin` certificate principal; Linode LISH as vpnsvcs break
glass; the 30-day offline limit for Bitwarden clients (2022 blog post only).

## Comments

- 2026-10-13: The Problem's second consequence was stale when filed: `b02f3a8`, the commit that
  added this ticket, had already replaced the SOPS recipe in `docs/debugging.md` with a typed
  `read -rs` prompt. That recipe works. The `<host>_root_pswd` keys are not to be added to SOPS.
  The prompts in `secret_update.sh`, `tools/upload_src.sh` and the recipe now say whose password
  they want: `manualadmin`'s sudo password, not root's. The first-run bootstrap of `ssh_cert_gen.sh`
  (finding 3 in the notes) is documented in the pve1 guide's CA certs section and the recovery
  guide's Nothing escrowed path.
