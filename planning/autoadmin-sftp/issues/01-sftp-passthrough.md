# 01. The dispatcher's sftp passthrough gives autoadmin keys file access

Status: ready-for-agent Type: research Repo: homelab Source: architecture review 2026-10-10

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
