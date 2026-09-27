# Vaultwarden

Self-hosted Bitwarden-compatible password manager on secsvcs (pve1). This is what the
`vault` stubs refer to:
- `src/secsvcs/install_svcs.sh` `vault)` case (`echo "TODO: Implement vault"`);
- `src/secsvcs/dispatcher.sh` `install_vault` and its `install_all_svcs` entry;
- the commented router and service in `src/secsvcs/traefik/routes.yml.j2`;
- `docs/guides/secure_services.md.j2`;
- `docs/services.md` ("`vault` has an install stub but is not implemented").

Maintainer request 2026-09-26. Public exposure approved after checking the Vaultwarden
hardening guidance; see the assessment in 01. It replaces ci-and-docs/05 (wontfix "remove the
install_vault stub").

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-install-vaultwarden.md) | Install Vaultwarden on secsvcs (replaces the `vault` stub), publicly reachable | `ready-for-agent` | task |
