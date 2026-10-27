# 01. Give each VM a root-only secrets key, separate from manualadmin's SSH key

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-26

## Problem

The podman guide sets up the decryption key with `cp /home/manualadmin/.ssh/id_ed25519*
/etc/opt/secrets`. One key ends up doing two jobs:

- **The login key.** It's created by the debian guide, has no passphrase, is loaded into
  `ssh-agent`, and stays readable by `manualadmin`.
- **The age identity.** `get_secret.sh` and `list_secrets.sh` decrypt with
  `/etc/opt/secrets/id_ed25519`. pve1 encrypts each host's file to `<host>_id_ed25519.pub`.

Anyone with a `manualadmin` shell can therefore decrypt every one of that host's secrets without
the sudo password, given the ciphertext. `secret_update.sh` no longer stages a copy in `~`, so the
ciphertext is only in root's `/etc/opt/secrets/`, but the key is still exposed. A leaked login key
is also a leaked secrets key, and rotating one rotates the other.

## Plan

Use a native age key per VM, generated as root and never leaving `/etc/opt/secrets/` except in
backups.

1. **Code**
   - `get_secret.sh` and `list_secrets.sh` decrypt with `/etc/opt/secrets/age.txt`.
   - `secrets_lib.sh` encrypts to `${secrets}/<host>_age.pub`.
   - The podman guide runs `age-keygen -o /etc/opt/secrets/age.txt` in place of the `cp`, then
     prints the recipient with `age-keygen -y`.
   - Update `docs/guides/pve1.md.j2`, `pve1_recovery.md.j2` and `docs/debugging.md` to use the new
     names.
2. **Migration, per VM.** Encrypt to both recipients while switching, so the host can decrypt
   throughout.
   - On the VM: `sudo age-keygen -o /etc/opt/secrets/age.txt`, then
     `sudo age-keygen -y /etc/opt/secrets/age.txt`, and copy that recipient to
     `/root/secrets/<host>_age.pub` on pve1.
   - On pve1, while both recipients are listed: run `secret_update.sh <host>` and push it.
   - Deploy the code change, restart one container with secrets and check it comes up.
   - Drop the old recipient and push again. Then remove `/etc/opt/secrets/id_ed25519*` on the VM
     and `<host>_id_ed25519.pub` on pve1.
3. **The login key.** Keep `~manualadmin/.ssh/id_ed25519` only if you SSH out from the VM. It's no
   longer a secrets key either way.

The backups already stage `/etc/opt`, and their encryption is unchanged, so `age.txt` is
included. vpnsvcs's `/etc/opt/secrets` is 711 for Headscale; `age.txt` stays 600.

## Acceptance criteria

- [ ] No VM's secrets decrypt with any key that `manualadmin` can read without sudo
- [ ] Every container that uses secrets starts after the switch, on every VM
- [ ] A new VM following the guides gets its own age key, and no login key is copied
