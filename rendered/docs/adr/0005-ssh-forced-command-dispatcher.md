# ADR 0005: SSH forced-command dispatcher instead of a config-management agent

Status: accepted (backfilled 2026-08-30; decision predates this record). The generation mechanism is
amended by [ADR 0006](0006-node-inventory.md): the dispatcher and sudoers are both rendered from the
node inventory (`src/nodes/<node>/inventory.yml`). Amended 2026-10-10: no sftp passthrough; data
moves on the commands' stdin and stdout, and the commands that carry secrets or trust anchors answer
only pve1's certificate (see [Amendment](#amendment-2026-10-10-file-transfer-and-key-id-gating)).

## Context

Deploys and admin actions (install a service, distribute certs, wake a VM) must run as root on
remote nodes, triggered by scripts and by OliveTin buttons. Ansible-style agents or unrestricted
SSH-as-root would mean any compromised automation credential can run arbitrary commands on every
node.

## Decision

Two accounts per node. `manualadmin` is for interactive human use. `autoadmin` is the automation
account: its SSH key is bound to a `ForceCommand` script, `dispatcher.sh`, that matches
`$SSH_ORIGINAL_COMMAND` against an exact whitelist (`install_traefik`, `install_all_svcs`,
`copy_acme_certs`, …) and rejects anything else. The node's sudoers file is *generated from the
dispatcher itself* (`tools/parse_dispatcher.sh` at render time), granting `autoadmin` NOPASSWD for
exactly the whitelisted commands. `tools/gen_dispatch_cmds.sh` derives dispatcher cases from
`install_svcs.sh` so the whitelist tracks the real service list. *Superseded by [ADR
0006](0006-node-inventory.md): both tools are gone; the dispatcher and sudoers are rendered from the
node inventory (`src/nodes/<node>/inventory.yml`).*

## Consequences

- A stolen automation key can only replay predefined, parameterless actions: no shell, no arbitrary
  commands, and the sudo grants can't drift from the whitelist.
- No agent daemon, no config-management runtime on the nodes; transport is plain SSH.
- Every new remote action requires touching the dispatcher (or regenerating it) and redeploying,
  which is deliberate friction.
- Do not "simplify" a node by giving `autoadmin` broader sudo; the narrow generated grant is the
  security model.

## Amendment 2026-10-10: file transfer and key-ID gating

The dispatchers used to exec `sftp-server` for the autoadmin key before the whitelist, so cert
distribution and the backup pull could scp files through `/home/autoadmin`. That gave any autoadmin
key, OliveTin's included, read and write access to everything autoadmin owned: the backup stage (host
keys, secrets files, root's `.ssh` on two nodes), the files the root install commands move into
place (an uploaded `ca_ssh_key.pub` becomes `TrustedUserCAKeys`), and `~/.bashrc` and `~/.ssh/rc`,
which bash and sshd run around the forced command, so a shell. `planning/autoadmin-sftp/01` has the
research.

Decision:

- No passthrough. The whitelist is the whole interface. Dispatcher chatter goes to stderr so stdout
  can carry data.
- Commands move data themselves, still parameterless: `backup` streams the stage as a tar with a
  `SHA256SUMS` manifest and deletes it; `copy_acme_certs` and `host_key` print a file; the
  `install_*` commands take their files on stdin, bundled by `src/base/debian/send_files.sh` and
  unpacked by `receive_files` into a private temp dir that must hold exactly the named regular files,
  each matching the manifest.
- Commands that move secrets or trust anchors carry `key_ids: [pve1]` in the inventory. sshd exposes
  the certificate a session logged in with (`ExposeAuthInfo`); the dispatcher reads its key ID and
  rejects any other. OliveTin's key (ID `olive_tin`) is back to parameterless triggers, and gets no
  button for gated commands. pve1 already holds every secret, so its key gains nothing new.
- `/home/autoadmin` is root-owned and `PermitUserRC no`: nothing writes there, so nothing can
  plant a startup file. autoadmin is not in the `sudo` group.
