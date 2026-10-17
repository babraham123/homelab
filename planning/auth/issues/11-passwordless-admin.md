# 11. Passwordless admin: NOPASSWD sudo behind FIDO keys, locked roots, SSH CA on YubiKeys

Status: ready-for-agent
Type: task
Repo: homelab
Source: auth/08 follow-up tasks 1–8, 10–13 (2026-10-13)

## Problem

auth/08 decided where every human-held secret lives, and that most of them should stop existing.
Its Answer lists the follow-ups; tasks 9 (pve2's PBS token, backup-and-dr/11) and 14 (the SOPS
comment) are done, and task 5 (the `ssh_cert_gen.sh` bootstrap step) is in the pve1 guide. The rest
are below. Full research and sources: `../research-08.md`.

Hardware: two YubiKeys with firmware 5.2.3 or later (FIDO2 `ed25519-sk`). The Mac needs Homebrew
`openssh`; Apple's build has no FIDO support.

## Change

### A. sudo without a password, gated by a hardware login key

1. Workstation key: `ssh-keygen -t ed25519-sk -O verify-required` on the Mac, in
   `docs/guides/mac_personal.md.j2`. `ssh_cert_gen.sh.j2`'s `local` signing adds
   `-O verify-required` and the principals `manualadmin,autoadmin,admin`.
2. pve1's root certificate loses `manualadmin`: `ssh_cert_gen.sh.j2:71` becomes `-n autoadmin,admin`.
   `secret_update.sh`'s install step (lines 25–37) moves into a dispatcher command,
   `install_secrets` with `pve1_file_transfer: true`, taking `secrets.yaml.age` on stdin like the
   other `install_*` commands, and running the Podman placeholder loop.
3. `manualadmin ALL=(ALL) NOPASSWD: ALL` beside the dispatcher's sudoers on every Debian node. The
   router's sudoers is separate; pfSense's admin is root already.
4. Drop the password prompts from `tools/upload_src.sh:45` and `secret_update.sh:27`. Replace
   `docs/debugging.md` "Remote sudo non-interactively" with a one-liner: sudo is passwordless for
   `manualadmin`. Update `CONTEXT.md` (manualadmin: "full sudo with password") and
   `docs/security.md` "Host access".

### B. Lock the password accounts

1. Debian VMs and vpnsvcs: `passwd -l root` and `passwd -l manualadmin` once the certificate login
   works (`UsePAM yes` keeps key logins alive). pve1 and pve2: lock `manualadmin` only; `root@pam`
   stays for the web UI. New installs (`docs/guides/debian.md.j2`): leave root's installer password
   empty, lock manualadmin after the CA is installed.
2. Break glass in `docs/debugging.md`: `qm guest exec` from the host, or the console with
   `SYSTEMD_SULOGIN_FORCE=1` / `init=/bin/bash`. Linode's LISH console for vpnsvcs (unverified).
3. TFA (TOTP or WebAuthn) on `root@pam` for pve1, pve2 and PBS, documented in
   `docs/guides/proxmox.md.j2`.
4. pfSense: SSH to "Public Key Only" and the `admin` principal from A1, so `upload_src.sh:20-21`
   and `ssh_cert_gen.sh.j2:48` stop prompting. Test the same principal on the gaming VM
   (`upload_src.sh:27-28`); keep its password prompt if Windows doesn't map it.

### C. Trust roots

1. SSH user CA on two FIDO keys: `docs/guides/pve1.md.j2` CA certs makes one
   `ed25519-sk` CA key per YubiKey (`-O application=ssh:homelab-ca`); `ca_ssh_key.pub` holds both
   public keys, one per line; `ssh_cert_gen.sh` signs with whichever handle file is present, with
   the YubiKey plugged into pve1. Losing one key means deleting its line. The YubiKeys join the
   inventory in `pve1_recovery.md.j2`.
2. Root X.509 CA offline: `/root/ca/private/ca.key.pem` moves to the escrow sticks only, excluded
   from pve1's `backup.sh` stage; its passphrase goes on paper, kept apart from the sticks.
   `pve1_recovery.md.j2` row for `ca.key.pem` ("Covered by": escrow only) and "Only the private CA
   is lost" updated. The intermediate CA keeps its passphrase, in Vaultwarden.

### D. Escrow and recovery docs

1. backup-and-dr/04's escrow list gains: the root CA key (only copy), `breakglass.txt` (pve1/pve2
   `root@pam`, pfSense admin, ACB device key and password, Linode account), and the paper items
   (escrow passphrase, escrow identity passphrase, root CA passphrase, Vaultwarden master
   password). The escrow age identity must be an X25519 identity wrapped with `age -p`, not a
   passphrase recipient (an scrypt stanza can't share a file with other recipients). The CA and
   SSH CA passphrase hand-notes come off the list.
2. `pve1_recovery.md.j2`: line 34 (passphrases: Vaultwarden + escrow for the intermediate, paper
   for the root, YubiKeys replace the SSH CA's), line 53 (ACB: Vaultwarden + `breakglass.txt`),
   lines 248–253 (passwordless sudo). backup-and-dr/09 needs no change.

## Acceptance

- `ssh manualadmin@HOST sudo -n true` succeeds from the Mac after a PIN and touch, and fails from
  a copied `~/.ssh` without the YubiKey.
- `ssh -o PubkeyAuthentication=no manualadmin@HOST` and `su -` on a VM are refused; `qm guest exec`
  still works.
- `/root/.ssh/id_ed25519-cert.pub` on pve1 lists no `manualadmin` principal;
  `secret_update.sh <host>` completes without a prompt.
- `ssh-keygen -L -f /etc/ssh/ca_ssh_key.pub` on a host shows two `sk-ssh-ed25519@openssh.com` CA
  keys; a certificate signed by either logs in.
- `ca.key.pem` is absent from pve1 and from the latest PBS host backup; present on both escrow
  sticks.
- `tools/upload_src.sh router` and `secret_update.sh` prompt for nothing.
- `pveum user tfa list root@pam` shows an entry on pve1 and pve2; PBS likewise.
- backup-and-dr/04's list and `pve1_recovery.md` match the per-secret table in auth/08's Answer.

## Comments
