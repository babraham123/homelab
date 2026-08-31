# ADR 0005: SSH forced-command dispatcher instead of a config-management agent

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

Deploys and admin actions (install a service, distribute certs, wake a VM) must run
as root on remote nodes, triggered by scripts and by OliveTin buttons. Ansible-style
agents or unrestricted SSH-as-root would mean any compromised automation credential
can run arbitrary commands on every node.

## Decision

Two accounts per node. `manualadmin` is for interactive human use. `autoadmin` is
the automation account: its SSH key is bound to a `ForceCommand` script,
`dispatcher.sh`, that matches `$SSH_ORIGINAL_COMMAND` against an exact whitelist
(`install_traefik`, `install_all_svcs`, `copy_acme_certs`, …) and rejects anything
else. The node's sudoers file is *generated from the dispatcher itself*
(`tools/parse_dispatcher.sh` at render time), granting `autoadmin` NOPASSWD for
exactly the whitelisted commands. `tools/gen_dispatch_cmds.sh` derives dispatcher
cases from `install_svcs.sh` so the whitelist tracks the real service list.

## Consequences

- A stolen automation key can only replay predefined, parameterless actions — no
  shell, no arbitrary commands, and the sudo grants can't drift from the whitelist.
- No agent daemon, no config-management runtime on the nodes; transport is plain SSH.
- Every new remote action requires touching the dispatcher (or regenerating it) and
  redeploying — deliberate friction.
- Do not "simplify" a node by giving `autoadmin` broader sudo; the narrow generated
  grant is the security model.
