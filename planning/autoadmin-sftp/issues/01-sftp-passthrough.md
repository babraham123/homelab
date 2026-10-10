# 01. The dispatcher's sftp passthrough gives autoadmin keys file access

Status: resolved Type: research Repo: homelab Source: architecture review 2026-10-10

## Problem

Every dispatcher (`src/nodes/*/dispatcher.sh.j2`, router's and gaming's `Dispatcher.ps1.j2`
included) execs `sftp-server` for the autoadmin key before the whitelist `case`. So any holder of
an autoadmin key, OliveTin's included (`-I olive_tin -n autoadmin` in
`src/base/certificates/ssh_cert_gen.sh.j2`), can read, write and delete whatever autoadmin can.
ADR 0005 and `docs/security.md` ("Host access: the SSH dispatcher") say a stolen key can only
replay predefined, parameterless actions; that is false today.

What the passthrough exposes, found on the pre-restructure tree (re-verify each on the current
one):

- **Secrets read.** `stage_finish` (`src/base/debian/backup_lib.sh`) chowns the backup stage to
  autoadmin so pve1 can `sftp get` it. The stage holds `/etc/opt` (host secrets key and bundle),
  `/etc/ssh` host private keys, volume copies and Headscale's keys, and `files/` stays on the node
  between runs, so no `backup` run is needed first. `copy_acme_certs`
  (`src/base/debian/commands.sh.j2`) leaves `acme.json` in autoadmin's home and never removes it.
- **Trust-anchor swap.** `install_ssh_ca`, `install_ca`, `install_keys`/`install_certs` and
  `install_olive_tin_cert` install files from `/home/autoadmin` as root. An uploaded CA becomes
  `TrustedUserCAKeys` (manualadmin shell), an uploaded `ssh_known_hosts` enables MITM, uploaded
  TLS/mTLS keys replace the real ones.
- **Root on vpnsvcs (old tree).** `install_geoip_generator` moved `~/haproxy-mapper` to
  `/usr/local/bin`, which a root timer ran. geoip_generator is now a quadlet built on the VPS;
  check whether any install case still consumes an uploaded binary.
- **Persistence and tampering.** A planted `~/.ssh/authorized_keys` outlives cert revocation;
  `-rm`/overwrite of the stage poisons backups; gaming's `Dispatcher.ps1` is owned by autoadmin,
  so overwriting it gives arbitrary PowerShell.

## Legitimate uses to keep working

| Caller | Node | Needs |
|---|---|---|
| `backup_orchestrator.sh.j2` (automated, pve1) | 5 nodes | read and delete `/var/opt/backups` |
| `acme_transfer.sh.j2` | sec/home/websvcs; pve2, router | read `~/acme.json`; write `*.pem`/`*.key` |
| `ssh_cert_gen.sh.j2` | every node | read host pubkey; write CA, host cert, known_hosts; OliveTin key to secsvcs |
| `self_signed_cert_gen.sh.j2` | sec/web/homesvcs | write `~/*.pem` |
| `docs/guides/pve1.md.j2`, `pve1_recovery.md.j2` | every node | write `~/ca-chain.cert.pem` |

## Direction from the first pass

sftp-server flags don't fix it (`-R` breaks every upload; allowlists still expose the stage) and
`ChrootDirectory` breaks the dispatcher's sudo. The candidate fix:

- Drop the sftp passthrough everywhere; move data through whitelisted commands' stdout/stdin.
- `backup` streams the stage as a tar on stdout; the stage stays root-owned and the node deletes
  it after sending. `stage_collect`'s local and remote paths become the same pipe. The
  dispatchers' own `echo`s move to stderr so they don't corrupt the stream.
- Reads (`acme_json`, `host_key`) become commands that `cat` the file.
- Uploads: `tar -c files | ssh autoadmin@host install_ssh_ca`; the command untars into a
  `mktemp -d` with `--no-same-owner` and accepts only the named regular files.
- Residual risk: the key that can run `backup` gets the secrets, and stdin installs still take any
  trust anchor. Gate `backup`, the reads and the stdin installs to pve1's certificate
  (`ExposeAuthInfo yes` plus a key-ID check in the dispatcher), so OliveTin's key is back to
  parameterless actions.

## Questions to answer

- Confirm or refute each exposure above on the current tree.
- Is the stdout/stdin design workable on the router (POSIX sh, bsdtar) and gaming (PowerShell)?
- Key-ID gating: `ExposeAuthInfo` vs another way to tell pve1's cert from OliveTin's.
- What else uses scp/sftp as autoadmin that the table misses.
- The ADR 0005 amendment and `docs/security.md` wording.

## Answer

Researched 2026-10-10 on main at `e591e8b`. The exposure is real and wider than the ticket says;
the stdout/stdin design works on every node, and `ExposeAuthInfo` is the right gate.

### Exposures on the current tree

| Claim | Verdict | Current tree |
|---|---|---|
| Secrets read | **confirmed** | `stage_finish` chowns the stage to autoadmin on every node but pve1 (`stage_init root`). `stage_fetch` deletes only `dumps/*/*`; `files/` sits on the node until the next run. It holds `/etc/opt` (every secrets file), `/etc/ssh` (host private keys), the volumes, and on pve2 and vpnsvcs `/root/.ssh`, so root's private key on both. `copy_acme_certs` leaves `~/acme.json` (ACME account and TLS keys) behind forever. |
| Trust-anchor swap | **confirmed** | `install_ssh_ca`, `install_ca`, `install_keys`, `install_certs`, `install_olive_tin_cert`, pve2's `install_certs_and_keys` and the router's `install_certs` all `mv` whatever is in `/home/autoadmin`, as root, by name. `install_ssh_ca` makes an uploaded file `TrustedUserCAKeys`, which signs `manualadmin` certs too. |
| Root on vpnsvcs | **refuted** | geoip_generator is a quadlet built from the rendered tree. No install case reads a binary from `/home/autoadmin`; the only consumers of that directory are the cert commands above. |
| Persistence and tampering | **confirmed, plus code execution** | `~/.ssh/rc` runs before the ForceCommand (`PermitUserRC` defaults to yes), and Debian's bash is built with `SSH_SOURCE_BASHRC`, so a `~/.bashrc` written over sftp runs on every autoadmin connection. Either gives an arbitrary shell as autoadmin, not just replay. `~/.ssh/authorized_keys` outlives the CA. gaming's `Dispatcher.ps1` is owned by autoadmin (`InstallAutomation.ps1` sets the owner), so overwriting it is arbitrary PowerShell. autoadmin is also in the `sudo` group (`docs/guides/debian.md`), which a shell plus the account password would use. |

Callers the table missed: none that scp as autoadmin. `ssh_cert_gen_windows.sh` and the router half
of `ssh_cert_gen.sh` go through `admin@` interactive sessions; `deploy_src.sh` already pipes stdin
into `archive_repo`, the pattern to generalise. gaming has no autoadmin upload at all, so its sftp
branch can simply go.

### Why sftp can't stay

`sftp-server -R` breaks every upload, `-p`/`-P` filter request types, not paths, and `-d` only sets
the start directory. `ChrootDirectory` is a Match-block setting that would chroot the dispatcher's
session too, and sudo doesn't work inside a chroot of `/var/opt/backups`. A sudo-wrapped `chroot`
around `sftp-server` needs the binary and its libraries inside the stage. All more moving parts than
one tar pipe.

### Design

1. **Delete the sftp branch** from `src/base/debian/dispatcher.sh.j2`, `src/nodes/router/
   dispatcher.sh.j2` and `src/nodes/gaming/Dispatcher.ps1.j2`. Move the dispatchers' `echo`s to
   stderr: stdout becomes a data channel (pve2's `install_certs_and_keys` already prints its
   fingerprint through it, with the "Request received" line mixed in).
2. **Backups: `backup` streams the stage.** `stage_init` always owns the stage as root (drop the
   `OWNER` argument and the `chown` in `stage_finish`). After `stage_finish`, a new `stage_send`
   runs `tar -C "$stage" -c .` to stdout and `rm -rf "$stage"`, so no secrets stay on the node
   between runs; everything backup.sh prints before that goes to stderr. On pve1, `stage_fetch`
   becomes `ssh autoadmin@NODE backup | tar -C "$tmp" -x` with `pipefail`, then the swap into
   `DEST/files` and `DEST/dumps`, and the local pve1 case runs its backup.sh through the same pipe.
   Symlinks come across now (sftp skipped them). The "newest dump only" trimming stays on pve1.
   Integrity: `stage_finish` writes `SHA256SUMS` of every file in the stage (`find -type f |
   xargs sha256sum`) before `stage_send` tars it, and pve1 runs `sha256sum -c --quiet` in the
   extracted tree before swapping it into `DEST`. ssh already protects the bytes in flight; the
   manifest catches a truncated stream, a tar that exited cleanly on a partial archive, and a stage
   changed under tar, and it goes to PBS with the files as a restore-time check. OliveTin's `backup`
   button would pour a tarball into its log, which the gate in step 5 prevents.
3. **Reads.** `copy_acme_certs` becomes `cat /etc/opt/traefik/certificates/acme.json` and
   `acme_transfer.sh` redirects it into `/root/acme/HOST.acme.json`; the copy in `~autoadmin` goes
   away. The host public key `ssh_cert_gen.sh` scps out is public: `ssh-keyscan -t ed25519 HOST`
   replaces it with no login at all.
4. **Uploads over stdin.** Callers run `tar -C DIR -c FILE... | ssh autoadmin@HOST install_X`. A
   `receive_files NAME...` helper in `src/base/lib.sh` extracts stdin into `mktemp -d` with
   `--no-same-owner`, fails unless the directory holds exactly the named regular files plus a
   `SHA256SUMS` (no subdirectories, links or extras), runs `sha256sum -c --strict` and requires
   every named file to be listed, then cds there; each `install_*` case keeps its existing `mv`
   lines. A `send_files NAME...` counterpart in `tools/lib.sh` and `src/base/lib.sh` writes the
   manifest and the tar, so callers are one line: `send_files ca_ssh_key.pub ... | ssh
   autoadmin@HOST install_ssh_ca`. Callers to convert: `ssh_cert_gen.sh` (`install_ssh_ca`, `install_olive_tin_cert`),
   `self_signed_cert_gen.sh` and `self_signed_key_gen.sh` (`install_certs`, `install_keys`),
   `acme_transfer.sh` (`install_certs_and_keys`, router `install_certs`), and the `install_ca`
   lines in `docs/guides/pve1.md.j2` and `pve1_recovery.md.j2`. Router: pfSense's `/bin/sh`,
   `mktemp -d` and bsdtar (`tar -xf - --no-same-owner`) all exist; its `install_certs` extracts into
   `/root` instead of moving from `/home/autoadmin`. gaming: nothing to convert.
5. **Gate pve1-only commands on the certificate's key ID.** Steps 1 to 4 close the file access,
   but they leave the secrets one command away: any autoadmin key can run `backup` and receive the
   whole stage (host keys, secrets files, root's `.ssh`) on stdout, or feed its own CA to
   `install_ssh_ca` on stdin. Three certificates carry the `autoadmin` principal: pve1's root key,
   the Mac's (`local`), and OliveTin's, whose private key sits in a volume on secsvcs next to a
   container that takes HTTP input. This step makes those commands answer only pve1's (or `local`'s)
   certificate, so OliveTin's key is back to what ADR 0005 promises: parameterless triggers, no data
   either way. The dispatcher can tell the certificates apart because sshd can expose the
   certificate it accepted. Add `ExposeAuthInfo yes` to the
   `Match User autoadmin` block (Debian and the router's `sshd_extra`; it is a Match keyword). sshd
   then writes `publickey ssh-ed25519-cert-v01@openssh.com <base64>` to the file named by
   `$SSH_USER_AUTH`, and for certificate logins the blob is the whole certificate
   (`sshkey_format_text` → `to_blob_buf` writes `cert->certblob`). The dispatcher reads the key ID
   with `ssh-keygen -L -f <(cut -d' ' -f2- "$SSH_USER_AUTH")` (`Key ID: "pve1"`; the router uses
   a temp file instead of process substitution). Inventory entries get an optional `key_ids:
   [pve1]`; `nodes.jinja` renders the guard into the case, drops those cases from OliveTin's
   buttons, and `check_rendered.sh`'s button check skips them. Gate `backup`, `copy_acme_certs`,
   every `install_*` that takes stdin, and `install_dispatcher`; `archive_repo` on pve1 can stay
   open (append-only, trimmed to three). Key IDs today: `pve1`, `olive_tin`, `local`; allow
   `local` where a guide has the Mac run the command. `Match Address` was considered and rejected:
   pve1 reaches vpnsvcs over the public port 2202, so its source address is the home NAT, the same
   as OliveTin's.
6. **Harden the account while here (Debian nodes; gaming unchanged).** `PermitUserRC no` in the
   Match block, and drop autoadmin from the `sudo` group in `debian.md`. Root-own the home: sshd
   and bash read `~/.ssh/rc`, `~/.bashrc`, `~/.ssh/authorized_keys` and `~/.ssh/environment` from
   autoadmin's home around the forced command, so a writable home turns any future write (a bug
   in a `receive_files` caller, a new command) into a shell. Once step 4 lands nothing
   legitimately writes to `/home/autoadmin`, so `chown root:root /home/autoadmin && chmod 755`
   (maintainer decision 2026-10-10): done once by hand on each node, as a step of the autoadmin
   setup in `docs/guides/debian.md`, not by a dispatcher command.
7. **Docs.** Amend ADR 0005: the key replays parameterless actions, some of which carry data on
   stdin/stdout, and the ones that move secrets or trust anchors require pve1's certificate.
   Reword `docs/security.md` "Host access", `docs/services.md` (the "over sftp" line), the
   `backup_lib.sh` and `stage_fetch` comments, and `CONTEXT.md`'s dispatcher entry.

### Rejected alternative

Each node uploading its stage to PBS itself with its own token and namespace would remove the pull
entirely, but spreads the client encryption key (11) and PBS credentials to every node, and vpnsvcs
would need a route to pbs2. The pull keeps one key on pve1, which the restructure chose on purpose.

### Residual risk

After the change an autoadmin key can run the open commands and nothing else; OliveTin's key cannot
read the stage or push a CA. pve1's key can, as it must; pve1 already holds every secret. A planted
file in `/home/autoadmin` is no longer possible once the directory is root-owned.

Follow-up: split into tasks (dispatcher and sshd changes; backup pipe; cert scripts; docs), in that
order, each deployable with `install_dispatcher` first so a node never has the new client against
the old server.
