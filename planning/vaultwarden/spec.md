# Vaultwarden

Self-hosted Bitwarden-compatible password manager on secsvcs (pve1). This is what the `vault` stubs
refer to:
- `src/nodes/secsvcs/install_svcs.sh` `vault)` case (`echo "TODO: Implement vault"`);
- the `vault: {}` entry in `src/nodes/secsvcs/inventory.yml`, which generates the dispatcher's
  `install_vault` and its `install_all_svcs` entry;
- the commented routers and service in `src/nodes/secsvcs/traefik/routes.yml.j2`;
- `docs/guides/secsvcs.md.j2`;
- `docs/services.md` ("`vault` has an install stub but is not implemented").

Maintainer request 2026-09-26. Public exposure approved after checking the Vaultwarden hardening
guidance; see the assessment in 01 and the source check in
[research-01.md](research-01.md). It replaces ci-and-docs/05 (wontfix "remove the install_vault
stub").

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-install-vaultwarden.md) | Install Vaultwarden on secsvcs (replaces the `vault` stub), publicly reachable | `ready-for-human` (code in; deploy and run acceptance) | task |
