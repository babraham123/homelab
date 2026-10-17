# 01. Install Vaultwarden on secsvcs (replaces the vault stub), publicly reachable

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-09-26 ("the vault TODO sprinkled in a few places"; public if the
  Vaultwarden hardening guidance is sufficient)

Settings below are checked against Vaultwarden 1.37.4 and Authelia v4.39.28; sources for each are
in [research-01.md](../research-01.md).

## Exposure decision: public (maintainer decision 2026-09-26)

Assessed against the Vaultwarden wiki (Hardening Guide, Fail2Ban Setup, Enabling SSO, Disable
invitations) and the `.env.template` of 1.37.4. **Sufficient for public exposure**, with the
controls below. Reasons:

- **The vault is end-to-end encrypted.** Clients encrypt with a key derived from the master password
  (`PASSWORD_ITERATIONS` 600k), so a full server compromise yields ciphertext. The residual risk is
  an offline guess at a weak master password, which `SSO_MASTER_PASSWORD_POLICY` narrows.
- **Login goes through Authelia.** With `SSO_ONLY=true` the password grant is refused. Every login
  passes Authelia's two-factor policy, LLDAP group gate and regulation ban. The master password is
  still required to decrypt. The one non-SSO login left is a user's personal API key, which is
  random and not guessable.
- **Strict SNI is already true.** HAProxy routes by SNI and silently drops anything else, so
  `https://<VPS IP>` reveals nothing, which is the guide's Shodan concern.
- Bitwarden's own cloud runs on the same model on the public internet.

Remaining risk: an unauthenticated vulnerability in Vaultwarden itself. Mitigations: nightly scanned
updates (image-updater), non-root read-only container, `/admin` behind Authelia, and alerting.

## Change

- **Rename `vault` → `vaultwarden` everywhere the stub appears**, so the case, quadlet and container
  share one name and nobody confuses it with HashiCorp Vault. Keep the subdomain
  `vault.{{ site.url }}`. Places:
  - `src/nodes/secsvcs/inventory.yml`: replace `vault: {}`, keeping its place after grafana, with
    `vaultwarden: {subdomain: vault, admin: true, uptime: vaultwarden, uptime_path: /alive,
    uptime_tier: 1, upstream: docker.io/vaultwarden/server:latest}`. That drives the dispatcher,
    sudoers, `install_all_svcs`, HAProxy's SNI list, Authelia's two-factor admin rule, the Gatus
    check and image updates;
  - `src/nodes/secsvcs/install_svcs.sh` case;
  - `src/nodes/secsvcs/traefik/routes.yml.j2` routers and service;
  - `docs/guides/secsvcs.md.j2`;
  - `docs/services.md`.
- **Quadlet** `src/services/vaultwarden/vaultwarden.container.j2`, laid out like `grafana`'s:
  - `Image=localhost/vaultwarden/server:latest`, `AutoUpdate=local`;
  - `ContainerName=vaultwarden`, `HostName=vault.{{ site.url }}`,
    `IP={{ secsvcs.container_subnet }}.17` (next free; crowdsec has `.16`);
  - `AddHost=auth.{{ site.url }}:{{ secsvcs.container_subnet }}.6`, so Vaultwarden reaches
    Authelia's discovery, token and userinfo endpoints through Traefik, as Grafana and OliveTin do;
  - `NoNewPrivileges=true`, `DropCapability=all`, `ReadOnly=true`;
  - `User=1000`, `Group=1000`, `ROCKET_PORT=8080`: the image defaults to port 80 and grants no
    capability to bind it;
  - `HealthCmd=/healthcheck.sh` (it follows `ROCKET_PORT`) with Grafana's `Health*` settings;
  - only `vaultwardendata.volume` → `/data` mounted, nothing else.
- **Volume** `src/services/vaultwarden/vaultwardendata.volume` with `User=1000` and `Group=1000`.
  The image's `/data` is root-owned and Podman copies that ownership onto a new named volume, so
  without these the container can't write its own data.
- **Environment (hardening):**

  | Setting | Value | Why |
  | --- | --- | --- |
  | `DOMAIN` | `https://vault.{{ site.url }}` | SSO callback, links |
  | `DATABASE_URL` | secret `vaultwarden_db_url`, `postgresql://vaultwarden:…@<host>/vaultwarden`, host as in `lldap_db_url` | covered by `pg_dumpall` |
  | `SIGNUPS_ALLOWED` | `false` | no password registration |
  | `SSO_SIGNUPS_ALLOWED` | `true` | since 1.37.3 this, not `SIGNUPS_ALLOWED`, governs SSO account creation; the LLDAP group is the gate |
  | `INVITATIONS_ALLOWED` | `false` | org owners can't create accounts; a user logs in via SSO once before being added to an org |
  | `PASSWORD_HINTS_ALLOWED` | `false` | no hints stored at all (`SHOW_PASSWORD_HINT` is already `false` by default) |
  | `SSO_ENABLED` / `SSO_ONLY` | `true` / `true` | login only via Authelia two-factor |
  | `SSO_AUTHORITY` | `https://auth.{{ site.url }}` | must equal Authelia's `issuer` exactly, no trailing `/` |
  | `SSO_CLIENT_ID` / `SSO_CLIENT_SECRET` | secrets | startup fails if either is empty |
  | `SSO_SCOPES` | `openid profile email offline_access` | Authelia needs `offline_access` for refresh tokens (wiki) |
  | `SSO_PKCE` | `true` (default) | sends `S256` |
  | `SSO_SIGNUPS_MATCH_EMAIL` | `false` | on a fresh install the first SSO login is a signup, so no existing account ever needs associating by email |
  | `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION` | `false` (default) | prevents account takeover |
  | `SSO_MASTER_PASSWORD_POLICY` | `{"minComplexity":3,"minLength":12}` | enforced when the master password is set at SSO enrollment |
  | `SSO_AUTH_ONLY_NOT_SESSION` | `false` (default) | the session lives as long as Authelia's refresh token, so removing a user from `vaultwarden_access` ends it at the next refresh |
  | `IP_HEADER` / `IP_HEADER_TRUSTED_PROXIES` | `X-Forwarded-For` / `{{ secsvcs.container_subnet }}.6` | real client IP for rate limits (auth/06); 1.37.4 takes the rightmost untrusted entry, so a forged leading one is ignored |
  | `LOGIN_RATELIMIT_*`, `ADMIN_RATELIMIT_*` | defaults (10/60 s, 3/300 s) | explicit in the quadlet so they're visible |
  | `ADMIN_TOKEN` | secret `vaultwarden_admin_token_hash`, argon2id PHC from `vaultwarden hash` | `/admin` second factor after Authelia |
  | `ORG_CREATION_USERS` | maintainer's email, as Authelia sends it | |
  | `HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS` | `true` (default) | the icon fetcher can't probe the LAN (SSRF); the SSO client is exempt, so Authelia still resolves to `.6` |
  | `PUSH_ENABLED` | `false` (default) | no relay through Bitwarden's push service; phones sync on open or pull-to-refresh instead of live |
  | `EXTENDED_LOGGING` | `true` (default) | |
  | `LOG_LEVEL` | `warn,vaultwarden::api::identity=info` | plain `warn` drops the "logged in successfully. IP" lines |

  Pass every secret with `Secret=<name>,type=env,target=<VAR>`, never `Environment=`. In
  particular the `ADMIN_TOKEN` hash is full of `$`: Quadlet doesn't escape it and systemd expands
  it. Store the raw PHC string; the `$$` doubling in the wiki is a docker-compose escape and would
  corrupt it here.

  Secrets in `src/nodes/secsvcs/secrets_template.yaml`, named to the repo's convention:
  - `vaultwarden_pg_password`, alphanumeric only because it goes inside a URL, and
    `vaultwarden_db_url` built from it;
  - `vaultwarden_admin_token_hash`;
  - `vaultwarden_oidc_id`, `vaultwarden_oidc_secret` and `vaultwarden_oidc_secret_hash`, with
    Grafana's recipes. The id and hash also go to `authelia.container.j2` as
    `VAULTWARDEN_OIDC_ID` and `VAULTWARDEN_OIDC_HASH`.
- **`/admin` is read-only by policy.** Saving settings there writes `/data/config.json`, which
  silently overrides the quadlet's environment. Say so in the secsvcs guide; change settings in
  the quadlet.
- **Authelia** (`src/services/authelia/configuration.yml.j2`):
  - an authorization policy, because the built-in `two_factor` admits every user:

    ```yaml
    authorization_policies:
      vaultwarden:
        default_policy: 'deny'
        rules:
          - policy: 'two_factor'
            subject: 'group:vaultwarden_access'
    ```

  - a custom lifespan `vaultwarden` with `refresh_token: '30 days'`. The global
    `refresh_token: '90 minutes'` would end every Vaultwarden session after about 90 idle minutes;
  - OIDC client `vaultwarden`, from Authelia's Vaultwarden guide:
    - `redirect_uris: ['https://vault.{{ site.url }}/identity/connect/oidc-signin']`;
    - `scopes: ['openid', 'email', 'profile', 'offline_access']`;
    - `grant_types: ['authorization_code', 'refresh_token']`, `response_types: ['code']`;
    - `require_pkce: true`, `pkce_challenge_method: 'S256'`;
    - `token_endpoint_auth_method: 'client_secret_basic'`. Vaultwarden uses Basic whenever the
      provider offers it, so Grafana's `client_secret_post` would fail the token exchange;
    - `userinfo_signed_response_alg: 'none'`;
    - `authorization_policy: 'vaultwarden'`, `lifespan: 'vaultwarden'`.

    Don't copy the guide's `SSO_ROLES_*` variables or its `vaultwarden` claim: they belong to the
    OIDCWarden fork and the official image ignores them.
  - a new LLDAP group `vaultwarden_access`, documented in `docs/maintenance.md` "Add a new user"
    (ci-and-docs/04).
  - Authelia asks for consent on every SSO login, whatever `consent_mode` says, because the client
    gets refresh tokens. That's expected.
- **Clients:** check that the Bitwarden browser extension, desktop and mobile apps complete the SSO
  flow. The button reads "Use single sign-on" or "Enterprise single sign-on" depending on the
  client. Any organization identifier works, because Vaultwarden ignores it. On Linux, the desktop
  app needs a `bitwarden://` protocol handler in Chrome or Firefox to receive the redirect.
- **Traefik** (`src/nodes/secsvcs/traefik/routes.yml.j2`): uncomment and rename the stubs. Every
  router inherits `authelia@file` and `secure-headers@file` from the `&service` anchor, so each one
  sets `middlewares:` itself:
  - `vaultwarden`: `Host(vault.SITE)`, `middlewares: []`. No `authelia@file`, because clients call
    the API directly. No `secure-headers@file`, because Traefik's headers middleware replaces the
    app's headers: it would swap Vaultwarden's CSP and `X-Frame-Options` for the generic ones and
    add them to the connector pages the extension frames for WebAuthn and Duo;
  - `vaultwarden-notifications`: `Host(vault.SITE) && PathPrefix(/notifications/)`,
    `middlewares: []` and access logs off, because the websocket URL carries `access_token=<JWT>`
    and Traefik can't redact one query parameter. The Lua filter in
    `src/services/fluentbit/journald.lua.j2` redacts only what reaches VictoriaLogs;
  - `vaultwarden-admin`: `Host(vault.SITE) && PathPrefix(/admin)` with `authelia@file` only.
    `vaultwarden` is `admin: true` in the inventory, so Authelia requires two factors from every
    network, followed by the admin token;
  - service `vaultwarden` at `http://vault.{{ site.url }}:8080/`.
- **Postgres:**
  - add a `vaultwarden` block to `src/services/postgres/pg_init.sql`, ending with
    `ALTER DATABASE vaultwarden OWNER TO vaultwarden` so it keeps working on Postgres ≥15;
  - add `Secret=vaultwarden_pg_password,type=env,target=VAULTWARDEN_POSTGRES_PASSWORD` to
    `postgres.container.j2`;
  - `initdb.d` only runs on an empty cluster, so for the existing one, run the block once by hand
    with `podman exec postgres psql …`, and document that in the secsvcs guide.
- **Brute-force signal:** with `SSO_ONLY`, failed logins happen in Authelia, which the `auth` alert
  group in `src/services/vmalert/configs/homelab.yml` already covers. Vaultwarden's own signal is
  `Invalid admin token. IP: <ip>`, reachable only after Authelia. vmalert queries only
  VictoriaMetrics today, so a log-based rule needs a second vmalert pointed at VictoriaLogs. File
  that as an observability ticket rather than doing it here. No fail2ban: on secsvcs it can't
  block at the edge, which is HAProxy on the VPS.
- **Monitoring:** the Gatus check comes from the inventory entry. Add a Homepage entry.
- **Recovery:**
  - add `stage_volume vaultwardendata` to `src/nodes/secsvcs/backup.sh.j2`. The volume holds
    attachments, sends, `config.json` and `rsa_key*`, which existing sessions need. The DB is
    already in `pg_dumpall`;
  - list `vaultwardendata` with the other volumes in `docs/services.md`;
  - the plaintext admin token lives with the maintainer and in the escrow bundle
    (backup-and-dr/04). SOPS holds only its hash.

  Add a periodic **password-protected Bitwarden JSON export** to the escrow bundle
  (backup-and-dr/04), so the passwords needed to rebuild the homelab don't live only in the homelab.
  **SSO caveat:** with `SSO_ONLY`, new devices can't log in while Authelia is down.
  Already-logged-in clients keep their offline copy, and the escrow export covers the worst case.

Not adopted from the guide: hiding under a secret subdir. With `SSO_ONLY` and Authelia in front of
`/admin`, it adds friction for little gain.

## Acceptance

- `install_vaultwarden` via the dispatcher installs and starts it. `install_all_svcs` includes it
  after grafana, as the stub does today.
- From the internet (phone on mobile data): browser extension and mobile app log in via Authelia
  two-factor and its consent screen, then unlock with the master password and sync.
- A user not in `vaultwarden_access` is refused by Authelia.
- The password login is refused (`SSO_ONLY`). `/admin` requires Authelia and then the admin token.
- A logged-in extension is still signed in and syncing after 2 hours idle.
- `https://vault.SITE/` carries Vaultwarden's own `Content-Security-Policy`, not
  `secure-headers`' `frame-ancestors https://*.SITE`.
- `/notifications/hub` requests don't appear in Traefik's journal.
- `curl https://<VPS IP>` with no SNI gets dropped, not Vaultwarden.
- Vaultwarden logs show the client's real public IP.
- A `pg_dumpall` run includes the `vaultwarden` database, and a secsvcs backup stage includes
  `vaultwardendata`.

## Comments

- 2026-09-27: restructure/01 landed: the dispatcher, sudoers and `install_all_svcs` come from the
  node inventory, now `src/nodes/secsvcs/inventory.yml`. Rename the `vault: {}` entry under
  `services` to `vaultwarden: {subdomain: vault}` (add `uptime` for a Gatus check). There's no
  `gen_dispatch_cmds.sh` to run, and `secsvcs_subdomains` is now `inv.subdomains.secsvcs`.
- 2026-09-27: backup-and-dr/01 landed, so this is now blocked only on auth/06. The weekly
  orchestrator runs `pg_dumpall` on secsvcs before snapshotting the VM, so a Postgres-backed
  Vaultwarden is covered with no extra step. Data kept outside Postgres (attachments, `rsa_key*`) is
  in the secsvcs VM snapshot only; backup-and-dr/10 is where it gets a file-level copy.
- 2026-10-07 (observability/02): `access_token=` in `RequestPath` is redacted by
  `src/services/fluentbit/journald.lua.j2` before the line leaves the node.
- 2026-10-10: the Lua redaction only covers VictoriaLogs; the node's journal keeps the raw line. The
  websocket now gets its own router with access logs off (see **Traefik**).
- 2026-10-12: folded in [research-01.md](../research-01.md): 1.37.4, non-root volume ownership,
  no `secure-headers` on the Vaultwarden routers, a group-gated Authelia policy, Basic client auth,
  a 30-day refresh lifespan, `SSO_SIGNUPS_ALLOWED`, `AddHost`, and secrets passed with `Secret=`.
- 2026-10-12: no longer blocked by auth/06. The router routes tailnet traffic without SNAT through
  a System Patches change (router/04), so Traefik gets the real client IP; auth/06 stays open to
  watch for pfsense/FreeBSD-ports#1462 shipping.
- 2026-10-12: implemented: `src/services/vaultwarden/`, the inventory entry, the routers, the
  Authelia policy, lifespan and client, the Postgres block and secret, the secrets template, the
  backup stage, the Homepage entry, and a Vaultwarden section in the secsvcs guide (prerequisites,
  creating the database by hand, `/admin` read-only, the escrow export). The IP is `.17` because
  crowdsec already has `.16`. The log-based alert is observability/13; the escrow items are a
  comment on backup-and-dr/04. Left for the maintainer: fill the `vaultwarden_*` secrets, create
  the `vaultwarden_access` group, deploy per the guide, and run the acceptance list once auth/06
  has verified the client IP.
- 2026-10-17: body brought up to date: dropped the "Why it waits" section (auth/06 no longer
  blocks this) and the pre-auth/01 note on `/admin`; `vaultwarden` is `admin: true` in the
  inventory, so `/admin` needs two factors from every network.
