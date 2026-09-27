# 01. Install Vaultwarden on secsvcs (replaces the vault stub), publicly reachable

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-26 ("the vault TODO sprinkled in a few places"; public
if the Vaultwarden hardening guidance is sufficient)
Blocked by: backup-and-dr/01, auth/06

## Why it waits

- **backup-and-dr/01:** Vaultwarden data can't be recreated. Today PVE backups silently
  do nothing while pve2 is off, and Postgres has no logical dump. backup-and-dr/01,
  itself blocked by backup-and-dr/07 (`pg_dumpall`), fixes both.
- **auth/06:** rate limiting and Authelia's ban both key on the client IP. Behind
  HAProxy they are useless unless the real IP arrives.

## Exposure decision: public (maintainer decision 2026-09-26)

Assessed against the Vaultwarden wiki (Hardening Guide, Fail2Ban Setup, Enabling SSO,
Disable invitations, `.env.template` of 1.37.3). **Sufficient for public exposure**, with
the controls below. Reasons:
- **The vault is end-to-end encrypted.** Clients encrypt with a key derived from the
  master password (`PASSWORD_ITERATIONS` 600k), so a full server compromise yields
  ciphertext. The residual risk is an offline guess at a weak master password.
- **Login goes through Authelia.** With `SSO_ONLY=true` there is no password login
  endpoint to brute-force. Every login passes Authelia's two-factor policy, LLDAP group
  gate and regulation ban. The master password is still required to decrypt.
- **Strict SNI is already true.** HAProxy routes by SNI and silently drops anything
  else, so `https://<VPS IP>` reveals nothing, which is the guide's Shodan concern.
- Bitwarden's own cloud runs on the same model on the public internet.

Remaining risk: an unauthenticated vulnerability in Vaultwarden itself. Mitigations:
nightly scanned updates (image-updater), non-root container, `/admin` behind Authelia,
and alerting on logs.

## Change

- **Rename `vault` → `vaultwarden` everywhere the stub appears**, so the case, quadlet
  and container share one name and nobody confuses it with HashiCorp Vault. Keep the
  subdomain `vault.{{ site.url }}`, which puts it in `secsvcs_subdomains` and therefore
  on HAProxy. Places:
  - `install_svcs.sh` case;
  - `dispatcher.sh` `install_vaultwarden` and its `install_all_svcs` line (regenerate
    via `gen_dispatch_cmds.sh`);
  - `routes.yml.j2`;
  - the secsvcs guide (`secure_services.md.j2`, or `secsvcs.md.j2` if restructure/04
    has landed);
  - `docs/services.md`.
- **Quadlet** `src/vaultwarden/vaultwarden.container.j2`:
  - `Image=docker.io/vaultwarden/server:latest` (converted by image-updater/05),
    `ContainerName=vaultwarden`, `HostName=vault.{{ site.url }}`,
    `IP={{ secsvcs.container_subnet }}.16` (next free);
  - `NoNewPrivileges=true`, `User=1000:1000` with `ROCKET_PORT=8080` (non-root, no
    privileged port), `DropCapability=ALL`;
  - only `vaultwardendata.volume` → `/data` mounted, nothing else.
- **Environment (hardening):**

  | Setting | Value | Why |
  |---|---|---|
  | `DOMAIN` | `https://vault.{{ site.url }}` | SSO callback, links |
  | `DATABASE_URL` | `postgresql://vaultwarden:…@pgdb.{{ site.url }}/vaultwarden` | covered by `pg_dumpall` |
  | `SIGNUPS_ALLOWED` | `false` | no anonymous registration |
  | `INVITATIONS_ALLOWED` | `false` | org owners can't create accounts either; access = LLDAP group |
  | `SHOW_PASSWORD_HINT` | `false` | hints aid guessing |
  | `SSO_ENABLED` / `SSO_ONLY` | `true` / `true` | login only via Authelia two-factor |
  | `SSO_AUTHORITY` | `https://auth.{{ site.url }}` (must equal Authelia's `issuer`) | |
  | `SSO_SCOPES` | `openid profile email offline_access` | Authelia needs `offline_access` for refresh tokens (wiki) |
  | `SSO_SIGNUPS_MATCH_EMAIL` | `true` for first login, then `false` | per wiki: keep account association windows short |
  | `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION` | `false` | prevents account takeover |
  | `IP_HEADER` / `IP_HEADER_TRUSTED_PROXIES` | `X-Forwarded-For` / `{{ secsvcs.container_subnet }}.6` | real client IP for rate limits (auth/06) |
  | `LOGIN_RATELIMIT_*`, `ADMIN_RATELIMIT_*` | defaults (10/60 s, 3/300 s) | explicit in the quadlet so they're visible |
  | `ADMIN_TOKEN` | argon2id PHC hash | `/admin` second factor after Authelia |
  | `ORG_CREATION_USERS` | maintainer's email | |
  | `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS` | `true` | the icon fetcher can't be used to probe the LAN (SSRF) |
  | `EXTENDED_LOGGING`, `LOG_LEVEL=warn` | | failed logins reach VictoriaLogs via fluentbit |

  Secrets via SOPS: `vaultwarden_postgres_password`, `vaultwarden_admin_token_hash`,
  `vaultwarden_oidc_secret` (plus Authelia's hashed copy).
- **Authelia:**
  - OIDC client `vaultwarden` (redirect `https://vault.SITE/identity/connect/oidc-signin`,
    scopes above, PKCE), `authorization_policy: two_factor`;
  - restricted to a new LLDAP group `vaultwarden_access` (document it in
    `docs/maintenance.md` "Add a new user", ci-and-docs/04);
  - check that the Bitwarden desktop, mobile and browser clients complete the SSO flow
    (their "Enterprise single sign-on" button).
- **Traefik:**
  - main router `Host(vault.SITE)` with `secure-headers@file` and **without**
    `authelia@file`, because clients call the API directly;
  - second router `Host(vault.SITE) && PathPrefix(/admin)` with `authelia@file`, gated
    at `two_factor` (auth/01) and, for now, the current admin group
    until auth/01 lands.
- **Postgres:** add a `vaultwarden` user and DB block to `src/postgres/pg_init.sql`.
  `initdb.d` only runs on an empty cluster, so for the existing one, also run it once by
  hand with `podman exec postgres psql …`, and document that in the case.
- **Logs:** the websocket URL carries `access_token=<JWT>`. Redact it in Traefik access
  logs before they are stored (comment added to observability/02).
- **Brute-force alerting instead of fail2ban:** fail2ban on secsvcs can't block at the
  edge, which is HAProxy on the VPS, and `SSO_ONLY` moves login to Authelia anyway. Add a
  VictoriaLogs-backed alert on repeated Vaultwarden `Invalid admin token` or
  failed-login lines, alongside the auth alerts in observability/01.
- **Monitoring:** Gatus endpoint `https://vault.SITE/alive` (tier-1 list in
  observability/07), Homepage entry.
- **Recovery:** add to the backup-and-dr/09 inventory:
  - the `vaultwardendata` volume (includes `rsa_key*`, needed to validate existing
    sessions);
  - the `vaultwarden` DB (covered by `pg_dumpall`);
  - the `ADMIN_TOKEN` source.

  Add a periodic **password-protected Bitwarden JSON export** to the escrow bundle
  (backup-and-dr/04), so the passwords needed to rebuild the homelab don't live only in
  the homelab. **SSO caveat:** with `SSO_ONLY`, new devices can't log in while Authelia
  is down. Already-logged-in clients keep their offline copy, and the escrow export
  covers the worst case.

Not adopted from the guide: hiding under a secret subdir. With `SSO_ONLY` and Authelia
in front of `/admin`, it adds friction for little gain.

## Acceptance

- `install_vaultwarden` via the dispatcher installs and starts it. `install_all_svcs`
  includes it after grafana, as the stub does today.
- From the internet (phone on mobile data): browser extension and mobile app log in via
  Authelia two-factor, then unlock with the master password and sync.
- A user not in `vaultwarden_access` is refused by Authelia.
- The password login form is disabled (`SSO_ONLY`). `/admin` requires Authelia
  two-factor and then the admin token.
- `curl https://<VPS IP>` with no SNI gets dropped, not Vaultwarden.
- Vaultwarden logs show the client's real public IP.
- A `pg_dumpall` run includes the `vaultwarden` database.

## Comments
