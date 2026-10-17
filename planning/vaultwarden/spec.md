# Vaultwarden

Self-hosted Bitwarden-compatible password manager on secsvcs (pve1), at `vault.SITE`, replacing
the old `vault` install stub. It lives in:

- `src/services/vaultwarden/` (quadlet and data volume);
- the `vaultwarden` entry in `src/nodes/secsvcs/inventory.yml` (dispatcher's
  `install_vaultwarden`, `install_all_svcs`, HAProxy SNI, Gatus, image updates) and its
  `install_svcs.sh` case;
- the `vaultwarden*` routers in `src/nodes/secsvcs/traefik/routes.yml.j2`;
- the Authelia policy, lifespan and OIDC client in `src/services/authelia/configuration.yml.j2`;
- the "Vaultwarden" section of `docs/guides/secsvcs.md.j2` and the catalog row in
  `docs/services.md`.

Maintainer request 2026-09-26. Public exposure approved after checking the Vaultwarden hardening
guidance; see the assessment in 01 and the source check in
[research-01.md](research-01.md). It replaces ci-and-docs/05 (wontfix "remove the install_vault
stub").

## Issues

| # | Title | Status | Type |
| --- | --- | --- | --- |
| [01](issues/01-install-vaultwarden.md) | Install Vaultwarden on secsvcs (replaces the `vault` stub), publicly reachable | `ready-for-human` (code in; deploy and run acceptance) | task |
