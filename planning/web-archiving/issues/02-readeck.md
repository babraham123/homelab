# 02. Run Readeck on websvcs with Authelia OIDC

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-11

## Problem

linkding stores pages but has no reader view, highlights, EPUB export or mobile
reading app.

## Change

Follow "Add a new service" in `docs/development.md`, with Guacamole as the model for
an OIDC client on websvcs.

- `src/services/readeck/readeck.container.j2`:
  - `Image=codeberg.org/readeck/readeck:latest`, `ContainerName=readeck`,
    `HostName=read.{{ site.url }}`, `IP={{ websvcs.container_subnet }}.18`, port 8000,
    `NoNewPrivileges=true`, `AutoUpdate=local`.
  - Data: `/var/opt/readeck:/readeck` for `config.toml` and the database on the SSD, and
    `/srv/media/archive/readeck:/readeck/data/bookmarks` so the archived articles sit on the
    HDD array (maintainer decision 2026-10-12).
  - Set the server's public URL and trusted proxy (Traefik,
    `{{ websvcs.container_subnet }}.6`) and the OIDC settings. Readeck 0.23 added OIDC;
    take the exact keys from its 0.23.0 changelog and docs, not from memory.
- Authelia OIDC client in `src/services/authelia/configuration.yml.j2`, like Guacamole's:
  - Secrets `readeck_oidc_id`, `readeck_oidc_secret` and `readeck_oidc_secret_hash` go
    in `src/nodes/secsvcs/secrets_template.yaml`. The id and plain secret go in
    `src/nodes/websvcs/secrets_template.yaml`.
  - Mount the secrets in `authelia.container.j2` and `readeck.container.j2`.
- Authelia access rule: bypass `resources: ['^/api/']` on `read.{{ site.url }}` for
  the `internal` and `vpn` networks, like 01, so the browser extension and the iOS app
  can use tokens. Check whether Readeck's extension OAuth flow also needs non-`/api/`
  paths.
- `install_svcs.sh` case, `src/nodes/websvcs/inventory.yml` entry
  `readeck: {subdomain: read, uptime: readeck}`, Traefik router and service, Homepage
  tile, and the guide line.
- Backups: stage Readeck's data consistently in `backup.sh.j2`, using `readeck export`
  if it exists in this version, otherwise a SQLite `.backup` plus the data directory.

## Acceptance

- Readeck logs in through Authelia OIDC, and the account maps to the Authelia
  username.
- Saving from the Readeck browser extension and from the iOS app works from the LAN
  and the VPN.
- A backup run stages a restorable copy.

## Comments

2026-10-11, implemented in the repo; acceptance needs a deploy to websvcs.

- Checked against Readeck 0.23.4. The provider is set with env vars
  (`READECK_AUTH_OIDC_PROVIDERS_AUTHELIA_*`), and the callback is `/login/oidc`.
  Provisioning is on, and the groups map `readeck_admin=admin
  authelia_gen_access=user`. Readeck resets a linked user's group at every sign-in, so
  admins need `readeck_admin` in LLDAP. The Authelia client has a `readeck` claims
  policy that puts `preferred_username`, `email` and `groups` in the ID token.
- The extension and both apps use Readeck's own OAuth. Its machine endpoints are under
  `/api/oauth/`, plus `/.well-known/oauth-authorization-server`, so both are bypassed
  for the LAN and VPN. Its browser pages (`/authorize`, `/device`) go through Authelia
  as usual.
- Backups use a `dump_sqlite` snapshot plus `/var/opt/readeck`, `config.toml`
  included, rather than `readeck export`, matching linkding and Storyteller. The export
  doesn't contain the secret key that tokens depend on. To restore, put the directory back
  with the snapshot as `data/db.sqlite3`. The archived articles on the HDD array are not
  staged; snapraid parity is their only protection (maintainer decision 2026-10-12).
- The uptime check is `/api/info`, which needs no auth.
