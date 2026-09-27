# 05. Remove the install_vault stub

Status: wontfix
Type: task
Repo: homelab
Source: review finding 37

Maintainer decision: ignore for now. `install_vault` remains wired through
`src/secsvcs/{install_svcs.sh,dispatcher.sh}` as a no-op stub.

## Comments

- 2026-09-26: the stub is Vaultwarden, now planned in vaultwarden/01, which implements
  and renames it instead of removing it.
