# Research: verify vaultwarden/01 against primary sources

Checked 2026-10-12 against Vaultwarden `1.37.4` (tag commit `54a4080`), the Vaultwarden wiki at
commit `8216c0f`, Authelia `v4.39.28`, Podman `v5.4.2` (Debian trixie's package), Traefik
`v3.7.14` and systemd `v257`.

## Verdict

The ticket is mostly sound, but an agent following it as written would hit six problems:
- **Non-root `/data` breaks first start.** The image's `/data` is root-owned and Podman copies that
  ownership onto a new named volume, so `User=1000` can't write it.
- **`secure-headers@file` replaces Vaultwarden's own CSP and `X-Frame-Options`.** That includes
  the connector pages Vaultwarden deliberately leaves unrestricted.
- **Authelia `authorization_policy: two_factor` has no group gate.** `vaultwarden_access` needs a
  custom policy whose default is `deny`.
- **Authelia's repo-wide `refresh_token: '90 minutes'` ends SSO sessions after about 90 idle
  minutes**, unless the client gets a custom lifespan or Vaultwarden runs with
  `SSO_AUTH_ONLY_NOT_SESSION=true`.
- **No `AddHost` for `auth.SITE`.** Without it, Vaultwarden can't reach the issuer the way Grafana
  and OliveTin do.
- **Version and settings are stale.** The latest release is 1.37.4, not 1.37.3. It changes how
  `X-Forwarded-For` is parsed, and `SSO_SIGNUPS_ALLOWED` (new in 1.37.3) is missing from the
  ticket.

The suspicion was wrong: `IP_HEADER_TRUSTED_PROXIES` does exist.

VW = `https://github.com/dani-garcia/vaultwarden/blob/1.37.4`;
WIKI = `https://github.com/dani-garcia/vaultwarden/wiki/<Page>/8216c0f929b83dbf8fff3621ace691252a7da78a`;
AUTHELIA = `https://github.com/authelia/authelia/blob/v4.39.28/docs/content`.

## Claim check

| Ticket claim | Verified? | Correct value / note | Source |
|---|---|---|---|
| Assessed against `.env.template` of 1.37.3 | Outdated | Latest is **1.37.4** (2026-10-05). It fixes 7 security advisories, including two-factor auth and org revocation. `:latest` pulls it. | https://github.com/dani-garcia/vaultwarden/releases/tag/1.37.4 |
| SSO is in the stable image | Yes | The `sso` config block ships in the release build. | VW/src/config.rs#L816-L851 |
| `SSO_ENABLED` / `SSO_ONLY` = `true`/`true` | Yes | Both default to `false`. `SSO_ONLY` rejects `grant_type=password` ("SSO sign-in is required"). | VW/src/config.rs#L818-L820, VW/src/api/identity.rs#L68 |
| "With `SSO_ONLY` there is no password login endpoint" | Partly | `client_credentials` (personal API key) login still works with `SSO_ONLY`. The key is random, so this is low risk, but it is a non-SSO login path. | VW/src/api/identity.rs#L81-L87 |
| `SSO_AUTHORITY` = `https://auth.SITE`, must equal the issuer | Yes | Must match the discovery `issuer` exactly. No `/.well-known…` suffix and no trailing `/`. | WIKI Enabling-SSO-support-using-OpenId-Connect ("Configuration"); VW/.env.template#L524-L527 |
| `SSO_SCOPES=openid profile email offline_access` | Yes | Default is `"email profile"` and `openid` is implicit. The wiki gives exactly this value for Authelia, because `offline_access` is needed to get a refresh token. | VW/src/config.rs#L834; WIKI Enabling-SSO… ("Authelia") |
| `SSO_SIGNUPS_MATCH_EMAIL` "true for first login, then false, per wiki" | Misread | Default `true`. The wiki's "shortest time possible" advice applies only together with `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=true`. On a fresh install the first SSO login is a signup, not an association, so set `false` from day one. Also, Authelia always asserts `email_verified=true`. | WIKI Enabling-SSO… ("On SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION"); VW/src/api/identity.rs#L205-L300; AUTHELIA/integration/openid-connect/openid-connect-1.0-claims.md (email table, "assumed true") |
| `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false` | Yes (default) | This is the default. It's moot with Authelia, which always sends `email_verified`. | VW/src/config.rs#L826 |
| `SSO_PKCE` | Yes | Defaults to `true` and sends `S256`. | VW/src/config.rs#L838; VW/src/sso_client.rs#L205-L209 |
| `SSO_CLIENT_ID`/`SECRET` | Yes | Startup fails if either is empty, or if `SSO_AUTHORITY` is empty. | VW/src/config.rs#L1106-L1108 |
| `SIGNUPS_ALLOWED=false` | Yes | Default `true`. Since 1.37.3 it does **not** govern SSO signups; `SSO_SIGNUPS_ALLOWED` (default `true`) does. | VW/src/config.rs#L618,L822,L1520-L1540; https://github.com/dani-garcia/vaultwarden/pull/7272 |
| `INVITATIONS_ALLOWED=false`: "org owners can't create accounts" | Yes | Default `true`. With `false`, inviting a **non-existent** email fails ("User does not exist"). Existing users can still be added to orgs, so a user must log in via SSO once before being added to an org. | VW/src/api/core/organizations.rs#L1028-L1032; WIKI Disable-invitations |
| `SHOW_PASSWORD_HINT=false` | Yes (default) | Already the default. The setting that actually prevents hints is `PASSWORD_HINTS_ALLOWED=false` (default `true`). | VW/src/config.rs#L646-L650; VW/.env.template#L310-L317 |
| `IP_HEADER=X-Forwarded-For` | Yes | Default `X-Real-IP`; Traefik sends both headers. | VW/src/config.rs#L671 |
| `IP_HEADER_TRUSTED_PROXIES` exists | **Yes** | Added in 1.37.0 (PR #7472). Default `local`, which means any non-global address. Takes a comma-separated list of IPs/CIDRs. **1.37.4:** the client IP is the *rightmost* `X-Forwarded-For` entry that isn't a trusted proxy (previously the leftmost). | VW/src/config.rs#L674-L680; VW/src/auth.rs#L1080-L1157; release notes 1.37.0 and 1.37.4 |
| Login rate limit default 10/60 s | Yes | `LOGIN_RATELIMIT_SECONDS=60`, `LOGIN_RATELIMIT_MAX_BURST=10` | VW/src/config.rs#L779-L781 |
| Admin rate limit default 3/300 s | Yes | `ADMIN_RATELIMIT_SECONDS=300`, `ADMIN_RATELIMIT_MAX_BURST=3` | VW/src/config.rs#L789-L791 |
| `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=true` (SSRF) | Yes (default) | Already the default. The SSO client deliberately bypasses the block (`get_reqwest_client_builder(false)`), so an internal Authelia still works. | VW/.env.template#L384-L386; VW/src/sso_client.rs#L74; VW/src/http_client.rs#L38-L62 |
| `EXTENDED_LOGGING` | Yes (default) | Default `true`. | VW/src/config.rs#L736 |
| `LOG_LEVEL=warn` | Valid, but loses data | Default `info`. Failed-login and invalid-admin-token lines are `error!` and survive `warn`, but "User … logged in successfully. IP: …" is `info!` and is dropped. | VW/src/api/identity.rs#L597; VW/src/api/admin.rs#L221 |
| `ORG_CREATION_USERS` = maintainer email | Yes | Comma-separated emails, compared lowercased. Must match the email Authelia sends. | VW/src/config.rs#L1016-L1020,L1552-L1561 |
| `PASSWORD_ITERATIONS` 600k | Yes | Default `600_000`; minimum `100_000`. | VW/src/config.rs#L644,L972 |
| `ROCKET_PORT=8080`, non-root needs a non-privileged port | Yes | The image sets `ROCKET_PORT=80`. The 1.37.4 Dockerfile does no `setcap`, despite what the Hardening Guide says. The healthcheck reads `ROCKET_PORT`, so it follows the change. | VW/docker/Dockerfile.debian#L172-L190; VW/docker/healthcheck.sh |
| `DATABASE_URL=postgresql://user:pass@host/db` | Yes | Format is correct. Since 1.37.0 an unrecognised URL is rejected rather than silently falling back to SQLite. The password must be URL-safe (see repo mismatches). | VW/.env.template#L61-L66; release notes 1.37.0 (PR #7061) |
| `ADMIN_TOKEN` = argon2id PHC | Yes | `vaultwarden hash` generates it. Doubling `$` to `$$` is a docker-compose escape only; don't do it for a Podman secret. | VW/.env.template#L430-L437; WIKI Enabling-admin-page |
| `User=1000:1000` | Works, non-canonical | Quadlet passes `User` verbatim to `--user`. The documented form is `User=1000` plus `Group=1000`. | https://github.com/containers/podman/blob/v5.4.2/pkg/systemd/quadlet/quadlet.go#L1669-L1692 |
| `NoNewPrivileges`, `DropCapability`, `IP`, `HostName` are quadlet keys | Yes | All are valid `[Container]` keys. | https://github.com/containers/podman/blob/v5.4.2/docs/source/markdown/podman-systemd.unit.5.md (table L280-L357) |
| Only `vaultwardendata.volume` → `/data` | Incomplete | The volume ends up root-owned; see correction 1. | see C1 |
| Authelia redirect `…/identity/connect/oidc-signin` | Yes | Generated from `DOMAIN`. | VW/src/config.rs#L1356-L1359; AUTHELIA/integration/openid-connect/clients/vaultwarden/index.md @ d8a1429 |
| Authelia client "scopes above, PKCE" | Incomplete | The official guide also sets `grant_types: [authorization_code, refresh_token]`, `token_endpoint_auth_method: client_secret_basic`, `public: false`, `pkce_challenge_method: S256`, `response_types: [code]`, and `userinfo_signed_response_alg: none`. | https://github.com/authelia/authelia/blob/d8a1429114126f445078e5d6114d3621e4995392/docs/content/integration/openid-connect/clients/vaultwarden/index.md |
| `authorization_policy: two_factor` plus restriction to the LLDAP group | Contradictory | Built-in `two_factor` admits every user. A group gate needs a custom `authorization_policies` entry (see correction 3). | AUTHELIA/configuration/identity-providers/openid-connect/provider.md (authorization_policies); …/clients.md (authorization_policy) |
| Clients' "Enterprise single sign-on" button | Partly | Vaultwarden returns a dummy org identifier and ignores `domain_hint`, so any identifier works. Labels vary: browser/desktop strings include "Use single sign-on" and "Enterprise single sign-on"; Android shows "Enterprise single sign-on". | VW/src/api/core/organizations.rs#L867-L877; VW/src/api/identity.rs#L1177-L1186,L1286; https://github.com/bitwarden/clients/blob/da62d9d26d53f00c44857a82ce00e55d3227c207/apps/browser/src/_locales/en/messages.json#L38-L55; https://github.com/bitwarden/android/blob/2cb8b8fa793a9d954acd35d4fcf2b193f8f38898/ui/src/main/res/values/strings.xml#L440 |
| "Master password is still required to decrypt" | Yes | The SSO wiki says the master password is still required and isn't controlled by SSO. There is no key-connector or trusted-device path. | WIKI Enabling-SSO… (intro) |
| Websocket URL carries `access_token=<JWT>` | Yes | `/notifications/hub?access_token=…`, also accepted as a header. `/notifications/anonymous-hub?token=…` carries a token too. Traefik proxies websockets with no extra config. | VW/src/api/notifications.rs#L122-L133,L206; VW/src/main.rs#L589; WIKI Hardening-Guide ("Access logs contain access_token"); WIKI Enabling-WebSocket-notifications |
| Redact the token in Traefik access logs | Partly | Traefik can't redact a single query parameter. It has `accessLog.fields.queryParameters.defaultMode` (`keep` or `drop`). Access logs are on (`src/services/traefik/static.yml.j2`), so the websocket gets a router with `observability.accessLogs: false`. | https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/install-configuration/observability/logs-and-accesslogs.md (L174-L176, L238) |
| `/alive` health endpoint | Yes | `GET`/`HEAD /alive`; it also checks the DB connection. | VW/src/api/web.rs#L243-L254 |
| `/admin` path | Yes | Mounted at `/admin`. A `Host && PathPrefix(/admin)` router has the longer rule and outranks the main router. | VW/src/main.rs#L585 |
| Main router needs nothing special | **No** | `secure-headers@file` overwrites Vaultwarden's CSP and `X-Frame-Options` (see correction 2). | see C2 |
| Strict SNI already holds | Yes | No or unknown SNI goes to `default_backend silent_drop_https`. | `src/services/haproxy/haproxy.cfg.j2` |
| `rsa_key*` lives in `/data` | Yes | `/data/rsa_key.pem`. `/data` also holds `attachments/`, `sends/`, `icon_cache/` and `config.json`. | VW/src/config.rs#L509-L519 |

## Corrections the ticket needs

1. **Volume ownership.** The image runs `mkdir /data` as root
   (VW/docker/Dockerfile.debian#L178). On first mount, Podman chowns a new named volume to the
   container user and then back to the image directory's owner, which is root
   ([libpod/container_internal_common.go#L2945-L3010 @ v5.4.2](https://github.com/containers/podman/blob/v5.4.2/libpod/container_internal_common.go#L2945-L3010)).
   Fix: put `User=1000` and `Group=1000` in `vaultwardendata.volume`. Quadlet turns these into
   `--opt uid/gid`, which also disables the chown
   ([parse.go @ v5.4.2](https://github.com/containers/podman/blob/v5.4.2/pkg/domain/infra/abi/parse/parse.go)).
   The alternative is `Volume=vaultwardendata.volume:/data:U`. In the container, use `User=1000`
   plus `Group=1000`.
2. **Don't put `secure-headers@file` on the Vaultwarden routers.** Traefik's headers middleware
   `Set`s headers, replacing the backend's
   ([unrolled/secure v1.0.9 secure.go#L477-L483](https://github.com/unrolled/secure/blob/v1.0.9/secure.go#L477-L483)).
   That swaps Vaultwarden's CSP (script-src, connect-src, and `frame-ancestors` allowing the
   extension origins) and `X-Frame-Options: SAMEORIGIN` for the repo's generic
   `frame-ancestors https://*.SITE` and deprecated `allow-from`. It also re-adds them to the
   `*-connector.html` pages, which Vaultwarden intentionally serves without them for the
   WebAuthn and Duo connectors (VW/src/util.rs#L51-L140). Use no headers middleware, or one
   that sets only HSTS.
3. **Group gate.** Add a custom policy and set `authorization_policy: 'vaultwarden'` on the
   client:
   ```yaml
   authorization_policies:
     vaultwarden:
       default_policy: 'deny'
       rules:
         - policy: 'two_factor'
           subject: 'group:vaultwarden_access'
   ```
   A `deny` match returns `access_denied` with no consent prompt
   (AUTHELIA/configuration/identity-providers/openid-connect/provider.md, authorization_policies).
4. **Authelia client fields.** Copy them from the official guide (commit `d8a1429`):
   - `grant_types: ['authorization_code', 'refresh_token']`. `offline_access` without the
     refresh grant yields no refresh token.
   - `token_endpoint_auth_method: 'client_secret_basic'`. Vaultwarden picks Basic whenever the
     provider advertises it (VW/src/sso_client.rs#L130-L137), so copying Grafana's
     `client_secret_post` from this repo would fail token exchange.
   - `require_pkce: true` and `pkce_challenge_method: 'S256'`.

   **Don't** copy the guide's `SSO_ROLES_*` env vars or its `vaultwarden` claim/scope. The page
   was tested against the OIDCWarden fork; upstream `config.rs` has no `sso_roles_*` keys, so
   they're ignored.
5. **Session lifetime.** With the default `SSO_AUTH_ONLY_NOT_SESSION=false`, the Bitwarden
   session lives only as long as Authelia's refresh token (WIKI Enabling-SSO…, "Session
   lifetime"). This repo sets `lifespans.refresh_token: '90 minutes'` globally
   (`src/services/authelia/configuration.yml.j2`). Pick one:
   - **Option a:** a custom lifespan (e.g. `refresh_token: '30 days'`) attached via the client's
     `lifespan:` (AUTHELIA/…/provider.md, lifespans.custom). Revoking LLDAP group membership
     then takes effect at the next refresh.
   - **Option b:** `SSO_AUTH_ONLY_NOT_SESSION=true`. Vaultwarden then uses its own 2 h access
     token and a 30-day idle refresh token (90 days on mobile), and removing a user from the
     group doesn't end existing sessions. The wiki says "7 days"; the code says 30
     (VW/src/auth.rs#L46-L48).
6. **Version.** Write 1.37.4. Keep `:latest`.
7. **`SSO_SIGNUPS_MATCH_EMAIL`.** Set `false` permanently. Drop the "true for first login"
   step; it's not what the wiki recommends and it isn't needed on a fresh install.
8. **Don't put the ADMIN_TOKEN hash in `Environment=`.** Quadlet doesn't escape `$` when it
   writes `ExecStart=` ([split.go escapeString @ v5.4.2](https://github.com/containers/podman/blob/v5.4.2/pkg/systemd/parser/split.go#L455-L492)),
   and systemd treats `$`/`$$` on command lines specially
   ([systemd.service.xml#L1442-L1478 @ v257](https://github.com/systemd/systemd/blob/v257/man/systemd.service.xml#L1442-L1478)).
   Use `Secret=vaultwarden_admin_token_hash,type=env,target=ADMIN_TOKEN` with the raw PHC
   string, no `$$`. `ADMIN_TOKEN_FILE` also works (VW/src/util.rs#L434-L447).
9. **The Traefik service URL port.** The commented stub in `routes.yml.j2` points at `:80`; it
   must be `http://vault.SITE:8080/`.

## Gaps the ticket misses

- **`SSO_SIGNUPS_ALLOWED=true`** (new in 1.37.3, default `true`). Set it explicitly. If anyone
  sets it `false`, the first SSO login fails with "Signups are disabled"
  (VW/src/api/identity.rs#L285-L297).
- **`AddHost=auth.{{ site.url }}:{{ secsvcs.container_subnet }}.6`**, as in
  `grafana.container.j2` and `olive_tin.container.j2`. Vaultwarden must fetch
  `https://auth.SITE/.well-known/openid-configuration`, and the token and userinfo endpoints.
  It calls userinfo for `email`/`preferred_username` (VW/src/sso.rs#L284-L293).
- **Explicit consent on every SSO login.** Authelia forces explicit consent whenever a refresh
  token is granted (`offline_access`), whatever `consent_mode` says
  (AUTHELIA/integration/openid-connect/frequently-asked-questions.md, "Why does Authelia ask for
  Consent…", item 1). Say so in the acceptance steps.
- **`PASSWORD_HINTS_ALLOWED=false`** stops hints being stored at all; `SHOW_PASSWORD_HINT` is
  already `false` by default.
- **`SSO_MASTER_PASSWORD_POLICY`**, e.g. `'{"minComplexity":3,"minLength":12,…}'`, enforced
  when the master password is set at SSO enrollment (`enforceOnLogin` isn't supported). It
  directly targets the residual risk the ticket names, an offline guess at a weak master
  password (VW/.env.template#L545-L546).
- **Admin-panel saves override env vars.** Saving settings in `/admin` writes
  `/data/config.json`, which overrides the quadlet's env and only logs a warning
  (VW/src/config.rs#L279-L295). Either treat `/admin` as read-only (document it) or back up
  `config.json` with the volume.
- **`LOG_LEVEL`.** To keep successful-login audit lines, use
  `warn,vaultwarden::api::identity=info` or `info`.
- **Optional `SSO_CLIENT_CACHE_EXPIRATION`.** Default `0` re-fetches discovery on every SSO
  call; the wiki suggests ~`600` (WIKI Enabling-SSO…, "Client Cache"). This is harmless for
  Authelia.
- **Mobile sync.** The mobile apps don't get live sync without `PUSH_ENABLED=true` plus an
  installation ID/key from bitwarden.com/host, which relays through Bitwarden's push service
  (WIKI Enabling-Mobile-Client-push-notification). Decide explicitly; leaving it off means
  manual or periodic sync on phones.
- **Desktop SSO caveats.** Chrome and Firefox on Linux need protocol-handler setup for the
  `bitwarden://` redirect (WIKI Enabling-SSO…, "Desktop Client"). Add this to acceptance notes.
- **SMTP is unspecified.** Without mail, users don't get Vaultwarden's email-change prompts on
  SSO login (WIKI Enabling-SSO…, "Account and Email handling") or invite emails. That's fine,
  but state it.
- **Vaultwarden-native 2FA still runs after SSO** if a user enables it
  (VW/src/api/identity.rs, "Will trigger 2FA flow if needed"). Optional; Authelia already
  enforces two factors.
- **Alert strings** (from code; the Fail2Ban wiki regexes match):
  - `Invalid admin token. IP: <ip>` (VW/src/api/admin.rs#L221);
  - `Username or password is incorrect. Try again. IP: … Username: …` (VW/src/api/identity.rs#L382);
  - SSO failures log `Login failure (…)` lines (VW/src/api/identity.rs#L208-L266).

  With `SSO_ONLY`, password-failure lines won't appear; brute-force signal lives in Authelia.
- **Postgres ≥15.** `GRANT ALL ON DATABASE` no longer grants CREATE on `public`
  (https://www.postgresql.org/docs/release/15.0/). The current image is `14-alpine`, so this is
  fine today; `ALTER DATABASE vaultwarden OWNER TO vaultwarden` makes it upgrade-proof.

## Repo-state mismatches

Re-checked after rebasing on main (restructure into `src/base`, `src/nodes`, `src/services`;
image-updater; Traefik access logs).

- **Paths:** the stub lives in `src/nodes/secsvcs/inventory.yml` (`vault: {}` after grafana),
  `src/nodes/secsvcs/install_svcs.sh`, `src/nodes/secsvcs/traefik/routes.yml.j2` (commented
  `vault` and `vault-notifications` routers, service on `:80`), `docs/guides/secsvcs.md.j2` and
  `docs/services.md`. Postgres and Authelia are under `src/services/`.
- **`.16` is free and `.6` is Traefik** (olive_tin is `.15`).
- **Main router override.** Every secsvcs router inherits `authelia@file` and
  `secure-headers@file` from the `&service` anchor, so each Vaultwarden router sets
  `middlewares:` itself (see correction 2).
- **Secret names:**
  - Postgres passwords are `<svc>_pg_password`, so `vaultwarden_pg_password`, not
    `vaultwarden_postgres_password`.
  - `postgres.container.j2` also needs a
    `Secret=vaultwarden_pg_password,type=env,target=VAULTWARDEN_POSTGRES_PASSWORD` line for
    `pg_init.sql`.
  - OIDC clients use `*_oidc_id`, `*_oidc_secret` and `*_oidc_secret_hash`, the id and hash wired
    through `authelia.container.j2` and `mustEnv`.
- **`DATABASE_URL` needs a URL-safe password.** The repo's Postgres password recipe still
  includes `# % : ? [ ]`, which break URL parsing. Generate an alphanumeric password and store a
  pre-built URL secret, as `lldap_db_url` does.
- **Image convention.** Quadlets now use `Image=localhost/…` plus `AutoUpdate=local`, with the
  pulled image in the inventory's `upstream:` key.
- **Gatus entry.** It needs `uptime_path: /alive`.
- **`/admin` is not two-factor everywhere yet.** Authelia's `access_control` grants
  `group:authelia_gen_access` `one_factor` from `internal`/`vpn` and `two_factor` elsewhere.
  Until auth/01 lands, `/admin` from the LAN is one-factor plus the admin token.
- **Log-based alerts.** vmalert's only datasource is VictoriaMetrics, so a rule on Vaultwarden
  log lines needs a second vmalert pointed at VictoriaLogs.
- **Backups.** backup-and-dr/10 stages named volumes with `stage_volume` in
  `src/nodes/secsvcs/backup.sh.j2`; `vaultwardendata` needs a line there.
