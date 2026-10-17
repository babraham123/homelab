# auth/13 research notes: ntfy and ntfy-idp-push credentials, TLS, and routes behind Authelia

Research for [13-ntfy-push-credentials-and-routes.md](issues/13-ntfy-push-credentials-and-routes.md),
first checked 2026-10-14; repo citations re-checked 2026-10-17 against `60cb3bb`. Every claim
about the repo cites a file and line.
Every other claim cites a source ID, collected under [Sources](#12-sources). INFERENCE marks my own
reading; UNVERIFIED marks a claim I couldn't confirm in a primary source.

**Updated 2026-10-17 for ntfy-idp-push v0.2.0 (`331e7e9`).** The first pass read the shim at
`3ed310f`. What changed since, and where it lands below:

| Change in the shim or its plan | Effect on this research |
| --- | --- |
| No TLS in the shim at all: ACME removed, then the HTTPS listener; the image listens on plain HTTP :8080 and its healthcheck defaults to `http://127.0.0.1:8080/healthz` [SH1] | Traefik terminates TLS; the image needs no overrides (§1, §8) |
| Forward-auth is the only sign-in: OIDC removed (`606c231`, `ddd9bc1`). `identity-header` (default `Remote-User`) is believed only from `trusted-proxies`; `auth-mode` and `oidc-*` keys are gone [SH1] | No OIDC client secret (§3); `trusted-proxies` = Traefik (§5) |
| Routes split into two families: identity (`/enroll`, `/provision`, `/devices`) and token (`/token/*`, `/challenge/*`); `/enroll?code=` became `/token/<code>`, and `/enroll/{verify,resend,password,qr}` moved under `/token/` (`ddd9bc1`, `331e7e9`). Token routes never read the identity header [SH1] | Prefix routing at Traefik; the old code-flow blocker is gone; Authelia's bypass header leak no longer reaches anything that trusts it (§5, §8) |
| The shim's README now recommends Authelia `bypass` for `^/token/`, `^/challenge/`, `^/auth/v2/`, `^/static/` [SH1] | Fine for the token family; not for `/auth/v2/` in this repo (§5) |
| Decision: ask Authelia to skip Duo's CA pinning when `duo_api.hostname` isn't a Duo host [SH2]; the shim's docs now state it as a prerequisite [SH1] | **Q3**: the existing Let's Encrypt resolver; GTS only as a fallback (§4, §7) |
| Live test of the pinned clients: GTS ECDSA (leaf → WE1 → GTS Root R4) passes; GTS RSA and Let's Encrypt fail [SH2] | Settles most of the fallback's chain question (§4) |
| Secrets from files: `<key>-file` and `NTFY_IDP_PUSH_<KEY>_FILE`, re-read on SIGHUP [SH1] | Shim secrets mount as files (§3, §8) |
| `backup <path>\|-` writes a consistent SQLite copy while serving [SH1] | secsvcs backup calls it instead of `stage_volume` (§11) |
| HSTS (1 year) and `nosniff` on every response [SH1] | One more reason not to add `secure-headers` (§7) |
| Releases: v0.1.1, v0.1.2, v0.2.0 on GitHub; multi-arch image `ghcr.io/babraham123/ntfy-idp-push:0.2.0` / `:0.2` [SH1] | Ticket 14 pulls it as an `upstream:` image; no build (§8, §11) |
| Still no metrics endpoint [SH1] | Ticket 14's scrape job stays out |

Upstream status, checked 2026-10-17:

| Item | State | Effect |
| --- | --- | --- |
| authelia#7647 [AU12] | Open. Reply posted 2026-10-17 proposing the shim and asking whether a PR that skips pinning for non-Duo hosts is acceptable; no maintainer answer yet | Q3's target waits on it |
| Authelia PR skipping pinning | None yet | Same |
| ntfy#597 enrollment codes | binwiederhier/ntfy#2068 open, no reviews yet [NT14]; stock ntfy has no `/account/token/redeem` | The shim falls back to plain topic links and `/provision/password` |
| ntfy header auth / OIDC (#1579, #1971, #1596) | All still open [NT9] [NT10] [NT11] | Q1 unchanged |

Versions that matter:

| Component | Version checked | Pinned by the repo |
| --- | --- | --- |
| Authelia | v4.39.28, the latest 4.39 tag; no 4.40 tag exists [AU1] | `authelia/authelia:4.39` (`src/services/authelia/authelia.container.j2:14`) |
| Traefik | v3.7.14, the latest 3.7 tag [TR1] | `traefik:v3.7` (`src/nodes/secsvcs/traefik/traefik.container.j2:13`) |
| ntfy | v2.30.0 upstream [NT1]; fork branch `token-enroll-codes` (ntfy#597), PR #2068 [NT13] [NT14] | `binwiederhier/ntfy:latest` (`src/services/ntfy/ntfy.container.j2:12`) |
| ntfy-idp-push | v0.2.0 (`331e7e9`, pushed) [SH1] | not deployed |
| duo_api_golang | v0.3.0, used by Authelia 4.39.28 (`go.mod:17`) [AU1]; the scratch `duoapi.go` copy is byte-identical [DU1] | — |

**The shim's `PLAN.md` no longer exists.** `~/Personal/ntfy-idp-push` has no `PLAN.md` in its tree
or history; the design now lives in `ARCHITECTURE.md` and `README.md` [SH1]. Section
references below are to those files and to the code.

## 1. The ticket's claims, checked

| Ticket claim | Verdict | Evidence |
| --- | --- | --- |
| `ntfy-ui` router at `routes.yml.j2:96-97` matches every `Mozilla/*` UA on `push.SITE` | Right, with an exception: `/file/` is excluded | `src/nodes/secsvcs/traefik/routes.yml.j2:96` is the comment, `:97` the `telemetry_ui` call with `!PathPrefix(`/file/`)` |
| `ntfy-auth@file` injects `Authorization: Basic admin:$NTFY_ADMIN_PASSWORD` | Right | `src/nodes/secsvcs/traefik/basic_auth.yml:9-12`; secret at `traefik.container.j2:32` |
| "Any Authelia-authenticated browser user is therefore ntfy admin" | **Wrong since auth/02.** Only `telemetry` group members get the admin header. Everyone else gets `s403` on *every* browser request, API calls included, so they can't use the web app at all | `routes.yml.j2:15-37` (parent `-ui`, child `-ui-telemetry` with `HeaderRegexp(`Remote-Groups`, …)`, child `-ui-denied` → `s403`); `docs/security.md:107-110` |
| The header overwrites the Bearer token the web app would send after signing in | Right for `fetch()` calls. WebSocket subscriptions send credentials as `?auth=`, which ntfy prefers over the header. Moot today: `enable-login: false`, so the web app has no session and every call is anonymous plus the admin header | `customRequestHeaders` sets the header; ntfy `readAuthHeader` replaces the header value with `?auth=` [NT2]; web app `Connection.js` adds `auth=` only when a user exists [NT3]; `src/services/ntfy/config.yml.j2.j2:257` |
| `duo_api` commented out at `configuration.yml.j2:342` | Right (block at `:338-348`) | `src/services/authelia/configuration.yml.j2:338-348` |
| Secret key as `AUTHELIA_DUO_API_SECRET_KEY` | Right; `_FILE` also works; so does `AUTHELIA_DUO_API_INTEGRATION_KEY` | §3 |
| Authelia pins Duo's CAs; Let's Encrypt is not in the bundle | Right. ISRG is absent; the only GTS roots present are **R2 and R4** (not R1, R3) | §4 |
| Matrix row: `idp-push.SITE/c/*` | **Wrong path.** The approve routes are `/challenge/{id}`, `/challenge/{id}/options`, `/assert`, `/deny`, `/fraud` | shim `internal/web/web.go:73-78` [SH1] |
| Matrix row: `idp-push.SITE/frame/qr` | **Wrong path.** It is `/token/qr`, used only by IdP-driven enrollment (authentik); Authelia never calls it | `web.go:71`; Authelia calls only `preauth` and `auth` [AU5] |
| Matrix row: `idp-push.SITE/enroll?code=…` | **Gone.** Code links are `/token/<code>` and post to `/token/begin` and `/token/finish` | `web.go:64-66`; shim `internal/routes/routes.go` [SH1] |
| Matrix: the shim's paths | **Incomplete.** Missing: `/static/` (the pages' JS), `/healthz`, `/enroll/begin`, `/enroll/finish`, `/token/verify/{device}`, `/token/resend`, `/token/password`, `/provision/password`, `/devices/{id}/revoke` | `web.go:56-83` |
| Matrix: Authelia `bypass` for the code link, `/c/`, … | **Was unsafe; harmless for the token family now.** On `bypass` Authelia still returns `Remote-User` for a one-factor session, but token routes never read it. Still wrong for `/auth/v2/` (§5) | [AU7] [AU8]; shim `ARCHITECTURE.md` "Provisioning" |
| Matrix: `idp-push.SITE/metrics` internal only | **No such endpoint**, still at v0.2.0; ticket 14's scrape job has nothing to scrape | [SH1] |
| `push.SITE/metrics` (port 2587) internal only | Right. With `metrics-listen-http` set, ntfy serves metrics only on that listener and not on :2586 | `config.yml.j2.j2:365-366`; ntfy `server.go:461-467` [NT2] |
| Problem 1: the shim needs ACME EAB credentials | **No.** The shim has no TLS at all: plain HTTP behind the proxy. EAB is needed only by the GTS fallback in Traefik (§4) | shim `README.md` "Reverse proxy and sign-in", `Containerfile` [SH1] |
| Problem 1: an OIDC client secret if `auth-mode: oidc` | **No.** The shim has no OIDC; forward-auth is the only sign-in | [SH1] |
| "Authelia pins Duo's CAs", treated as permanent | Pinning is a default of the client Authelia builds, not a property of the protocol; `SetCAPinning(false)` exists and the plan is to get Authelia to use it for non-Duo hosts | §4 [DU1] [SH2] |
| "The Duo client signs the configured hostname, so Traefik must not rewrite `Host`" | Right; Traefik passes `Host` through by default | §4 |

Ticket 14 errors found on the way (fix them there):

| Ticket 14 item | Problem | Evidence |
| --- | --- | --- |
| `auth-access` `idp-push:push-*:wo` for the admin `idp-push` | **ntfy refuses to start**: `auth-access` entries are only allowed for `user` roles. Admins already have full access; drop the entry | ntfy `cmd/serve.go:709-710` [NT5] |
| `tls-mode` key | No such key; the shim has no TLS settings, only `listen-http` (the image sets `:8080`) | shim `internal/config/config.go`, `Containerfile` [SH1] |
| `auth-mode: forward` | No such key; forward-auth is the only mode. `trusted-proxies` is required and `identity-header` defaults to `Remote-User` | shim `config.go:58-60,208-211` [SH1] |
| `ntfy-base-url: https://push.SITE` | The shim's container resolves `push.SITE` through aardvark to ntfy's container (§4.5), which listens on :2586, not :443. Needs `AddHost=push.{{ site.url }}:{{ secsvcs.container_subnet }}.6` | `ntfy.container.j2:28-29`; `routes.yml.j2:170-173` |
| Prometheus scrape job | No metrics endpoint (above) | — |
| `stage_volume ntfy_idp_push` | Works, but the shim's `backup -` gives a consistent copy of the passkey database while serving; use it like the `pg_dumpall` step | `src/nodes/secsvcs/backup.sh.j2:20-29`; shim `README.md` "Backup" [SH1] |
| Build from source with `github_build` | Not needed: v0.2.0 is released. Use `upstream: ghcr.io/babraham123/ntfy-idp-push:0.2`, like the other pulled images | `src/nodes/secsvcs/inventory.yml:5-30`; shim `README.md` "Releases" [SH1] |
| `/enroll?code=` bypass in Authelia | Code links are `/token/<code>` now; route the whole `/token/` family past Authelia (§8) | [SH1] |

## 2. Q1: replacing the `ntfy-auth@file` admin-header injection

### What hits the `ntfy-ui` router today

Browsers add their default `User-Agent` to every fetch [W1], and the WebSocket handshake is itself a
fetch [W2], so every request the web app makes carries the `Mozilla/…` UA. INFERENCE: every request
below except `/file/` matches `routes.yml.j2:97`.

| Request from the web app | Path | `Sec-Fetch-Mode` [W3] | Today, `telemetry` member | Today, anyone else |
| --- | --- | --- | --- | --- |
| Open the app, a topic, settings | `GET /`, `/app`, `/<topic>`, `/settings` | `navigate` | Authelia, then admin header | 403 page |
| App shell assets | `/static/*`, `/app.html`, `/config.js`, `/manifest.webmanifest` | `no-cors`/`cors` | admin header | 403 |
| Service worker script and its update poll | `/sw.js` (redirects are an error for the top-level script [W4]); `importScripts("/config.js")` (`web/public/sw.js:433`) | `same-origin` | admin header | 403 |
| Subscribe | `GET /<topics>/ws?auth=…` (`Connection.js:42,106`) | `websocket` | `?auth=` if signed in, else admin header | 403 |
| Publish, account, tokens, web push register | `PUT/POST /<topic>`, `/v1/account*`, `POST /v1/webpush` | `cors`/`same-origin` | admin header | 403 |
| Token redeem landing (ntfy#597) | `GET /account/token/redeem#code=…` | `navigate` | Authelia, admin header | 403 |
| Attachments | `/file/*` | any | `ntfy-api`, no Authelia | same |

So, yes: every API call a `telemetry` member's browser makes runs as ntfy **admin** (admins bypass
ACLs). The web app also breaks for everyone when the Authelia session expires: background `fetch`,
WebSocket and service-worker requests get a 302 they can't follow [W2] [W4].

Phones and services don't use this router: the ntfy apps, Home Assistant, ntfy-alertmanager and the
`ntfy_alert_token` scripts all send non-`Mozilla` UAs and their own credentials (INFERENCE from their
configs: `src/services/alertmanager/ntfy-alertmanager.scfg.j2.j2:68`,
`src/services/home_assistant/home_assistant.container.j2:40`,
`src/base/podman/image_updater.py.j2:122`).

### Options

| Option | Works? | Evidence | Verdict |
| --- | --- | --- | --- |
| **a1. ntfy trusts a proxy header** (`Remote-User` → ntfy user) | Not in any release. ntfy authenticates only `Authorization` (Basic/Bearer) or `?auth=` [NT2]. `auth-user-header` is a WIP PR by the maintainer, open since 2026-01-30 and idle since 2026-07-21, with an unsolved web-app race [NT10]. A second header-auth PR is open and disputed [NT11]. OIDC (ntfy#1596) is an open issue [NT9] | [NT2] [NT9] [NT10] [NT11] [NT12] | No |
| **a2. Traefik maps `Remote-User` to a per-user ntfy credential** | No built-in middleware maps one header to another through a table; `headers.customRequestHeaders` is static [TR11]. The repo's plugins are `rewriteHeaders` (regex rewrite of one header's own value) and CrowdSec (`static.yml.j2:43-48`). It could be faked with one multi-layer child router per user, each injecting that user's token (INFERENCE from [TR9]) | [TR9] [TR11] | No: one Traefik secret and router per person, and the web app still breaks on session expiry because API calls stay behind Authelia |
| **b. Authelia gates browser navigations only; the web app signs in to ntfy itself** | Yes. The SPA stores a session token and sends `Authorization: Bearer` / `?auth=` [NT3]. Sign-in is the ntfy login page (`enable-login`) or the ntfy#597 redeem link the shim's `/provision` hands out (shim `pages.go:72-76`) | [NT3] [NT7] [NT13] | **Recommended** |
| **c. No Authelia on `push.SITE`** | Yes; security is identical to (b), because ntfy (`auth-default-access: deny-all`, `config.yml.j2.j2:102`) is already the only boundary for every non-browser client (`routes.yml.j2:98-102`) | — | Acceptable fallback; (b) keeps the SSO feel |

Why the gate in (b) is a soft gate (INFERENCE from the sources): the shell is open-source static
code that must stay reachable without a session (the service worker refetches `/sw.js` and
`/config.js` and fails on redirects [W4]), and after the first visit the service worker serves `/`
from its cache (`NavigationRoute(createHandlerBoundToURL("/app.html"))`, `web/public/sw.js:439`)
[NT4]. ntfy's own auth protects the data.

### Matching navigations instead of the User-Agent

`Sec-Fetch-Mode` is set by the browser, can't be changed by page script, and is `navigate` exactly
for top-level navigations [W3]. A router rule ``Header(`Sec-Fetch-Mode`, `navigate`)`` therefore
sends Authelia only the requests where its 302 works, and leaves every `fetch`, WebSocket and
service-worker request to `ntfy-api`. A client that omits the header (old browser, curl) just skips
the gate, which costs nothing since ntfy enforces access (INFERENCE).

Exclusions from the gate, from the ntfy source:

| Path | Why it must skip Authelia |
| --- | --- |
| `/account/token/redeem` | The code is in the fragment (`tokenRedeem.js:20`) [NT13]. Through Authelia, the 302 inherits the fragment [RFC2], but the portal's post-login redirect to `rd` has none, so a not-yet-signed-in browser loses the code (INFERENCE) |
| `/file/*` | As today; attachment URLs are capabilities (`server.go:752`, no topic auth) |
| Non-navigation requests (`/static/*`, `/app.html`, `/sw.js`, `/config.js`, `/manifest.webmanifest`, `/docs/*`, `/v1/*`, `/<topic>/{json,sse,raw,ws,auth}`, publish, `/_matrix/*`) | Not `navigate`; ntfy's own auth applies (`server.go:644-782`) |

ntfy settings the web app needs: `enable-login: true` so the SPA shows its login page (the server
API at `/v1/account/login` doesn't check it: `EnableLogin` is only echoed to the web config,
`server_web.go:80`) and `require-login: true` so an anonymous SPA goes straight to it
(`App.jsx:68`, `cmd/serve.go:73,75`) [NT7]. `enable-signup` stays `false`.

### What changes for each existing ntfy user

| ntfy user / client | After (b) |
| --- | --- |
| `admin` | No longer used by Traefik. Keep it as a break-glass web-app login (password in Vaultwarden per auth/08), or drop it. Remove `ntfy_admin_password` from `traefik.container.j2:32` and `ntfy-auth` from `basic_auth.yml:9-12` |
| `alert` (Basic for ntfy-alertmanager, token for scripts) | Unchanged: never matched the UA rule |
| `hass` | Unchanged (Home Assistant's UA isn't `Mozilla`; UNVERIFIED, but irrelevant once routing no longer depends on the UA) |
| `person` (shared phone login) | Unchanged until each person has their own account from the shim's `/enroll` or `/provision` with the same grants (`config.yml.j2.j2:126-127` → `enroll-access`); then remove it |
| `telemetry` browser users | Lose silent admin. Sign in once with their own account (via `/provision`); see only what their ACL allows |
| Other Authelia users | Gain the web app (today: 403) after signing in to ntfy |
| ntfy-alertmanager's own UI (`ntfy-alertmanager.SITE`) | Unaffected (`routes.yml.j2:103-107`) |
| Web push | Registration checks read access once, with the caller's identity, and stores the subscription with that user (`server_webpush.go:59-72`); delivery does not re-check (`:89-105`) [NT6]. Subscriptions registered as `admin` keep delivering every topic they named until the browser re-registers or 60 days pass (`server/config.go:43-44`). Clear them at cutover (Follow-up 3) |
| Access logs | A signed-in SPA puts its token in the WebSocket URL (`?auth=base64(Bearer tk_…)`, `Connection.js:106`). Traefik logs the query (`static.yml.j2:19-29`); the Lua filter redacts only `access_token` (`src/services/fluentbit/journald.lua.j2:45`). Route `/…/ws` with `accessLogs: false`, as for Vaultwarden (`routes.yml.j2:116-124`) |

## 3. Q2: secret plumbing

| Secret | Consumers | Injection | Generate | Format constraints |
| --- | --- | --- | --- | --- |
| `ntfy_idp_push_password` (new) | ntfy | `render_secrets.sh` list (`ntfy.container.j2:47`) into `auth-users`, bcrypt-hashed like the others (`config.yml.j2.j2:117-121`) | the repo's 20-char `tr` line | Only ever hashed. `auth-users` is `name:hash:role`; username must match `^[-_.+@a-zA-Z0-9]+$`; bcrypt cost ≥ 10 (`cmd/serve.go:663-688`, `user/util.go`, `user/manager.go:42`) [NT5] |
| `ntfy_idp_push_admin_token` (new) | ntfy; shim | ntfy: `render_secrets.sh` into `auth-tokens` as `idp-push:<token>:ntfy-idp-push`. Shim: `Secret=ntfy_idp_push_admin_token` (mounted at `/run/secrets/`) plus `NTFY_IDP_PUSH_NTFY_ADMIN_TOKEN_FILE` | `ntfy token generate`, as for `ntfy_alert_token` (`secrets_template.yaml:61-62`) | `^tk_[-_A-Za-z0-9]{29}$` (32 chars; generator emits lowercase) (`user/util.go:24`, `user/manager.go:32-33`); `auth-tokens` is `user:token[:label]`, user must be provisioned (`cmd/serve.go:733-763`) [NT5]. Shim refuses to start unless the token is admin [SH1] |
| `duo_integration_key` (new) | Authelia; shim | Authelia: `Secret=…,type=env,target=AUTHELIA_DUO_API_INTEGRATION_KEY` (leave `integration_key` out of the YAML). Shim: `NTFY_IDP_PUSH_DUO_INTEGRATION_KEY` | `podman run --rm ghcr.io/babraham123/ntfy-idp-push:0.2 keygen` (prints both keys) | Shim emits `DI` + 18 `[A-Z0-9]` (`internal/config/keys.go:27`). Authelia checks only non-empty, no format (`validator/duo.go:14-38`) [AU2] |
| `duo_secret_key` (new) | Authelia; shim | Authelia: `…target=AUTHELIA_DUO_API_SECRET_KEY`. Shim: `Secret=duo_secret_key` plus `NTFY_IDP_PUSH_DUO_SECRET_KEY_FILE` | same `keygen` | 40 alphanumerics (`keys.go:30-32`); Authelia: non-empty only. Rotation: `duo-secret-key-previous` with `duo-key-grace` (shim `ARCHITECTURE.md` "Configuration") |
| OIDC client id/secret/hash | — | Not needed: the shim has no OIDC | — | — |
| `gts_eab_kid`, `gts_eab_hmac` (**fallback only**, §4) | Traefik (static config), not the shim | Static config can't be templated and file/CLI/env sources are mutually exclusive [TR6], so render the static file at start with `render_secrets.sh` (fallback task 1, §11) | `gcloud publicca external-account-keys create` → `keyId`, `b64MacKey` [GT4] | HMAC base64url, no padding [TR4] [RFC1]. **Single use**: one ACME account per key; void if unused for 7 days; the account then never expires [GT4] |

Authelia 4.39 details [AU3] [AU4]:

- Both `duo_api.integration_key` and `duo_api.secret_key` are secret keys (suffix `key`,
  `internal/configuration/const.go:85`). Each accepts `AUTHELIA_DUO_API_<KEY>` and
  `AUTHELIA_DUO_API_<KEY>_FILE`. Setting a `_FILE` secret *and* the YAML value is fatal
  (`sources.go:308-317`). The repo's plain-env pattern (`authelia.container.j2:38-44`) works for
  both.
- With `X_AUTHELIA_CONFIG_FILTERS=template` (`authelia.container.j2:32`), `mustEnv` returns `""`
  for any `AUTHELIA_*…KEY` variable (`templates/util.go:30-46`). Don't write
  `secret_key: '{{ mustEnv "AUTHELIA_DUO_API_SECRET_KEY" }}'`; use the env var directly.
- `hostname` has no runtime format check; a `host:port` value is passed verbatim (§4).
- Duo is auto-disabled only when all three fields are empty (`validator/duo.go`).

The shim takes its two secrets as files, not env: with `Secret=<name>` and no `type`, podman mounts
the secret at `/run/secrets/<name>` [PD4], and the shim reads `<KEY>_FILE`, trims the trailing
newline, refuses a value and a file for the same key, and re-reads the files on SIGHUP [SH1]. Its
`duo-integration-key` has no `-file` form, so it stays an env secret.

Podman: every key in the node's `secrets.yaml` becomes a podman secret through the shell driver
(`src/base/podman/containers.conf:8-12`, `list_secrets.sh:9`, `src/nodes/pve1/secret_update.sh:35`),
so the template entries in §10 plus `secret_update.sh` are all the plumbing needed.

## 4. Q3: TLS for the Duo API

### The plan: Authelia skips pinning for non-Duo hosts

duo_api_golang v0.3.0, which Authelia 4.39 already uses, has `SetCAPinning(false)`: it drops the
bundle and verifies against the system roots, so TLS verification stays on (`duoapi.go:189-197`)
[DU1]. The maintainer's decision (idp-review, idp-acme) is to ask Authelia to call it whenever
`duo_api.hostname` isn't Duo's, rather than make every shim operator find a pinned chain [SH2]. The
proposed change is one line in `internal/server/handlers.go` [AU1]:

```go
duoapi.NewDuoApi(ikey, skey, host, "", duoapi.SetCAPinning(isDuoHost(host)))
// isDuoHost: suffix .duosecurity.com or .duofederal.com
```

Status: the reply on authelia#7647 proposing this was posted 2026-10-17 and awaits the
maintainer [AU12]. No PR or release has it yet. Once one does, `idp-push.SITE` uses the existing
`le-http-production` resolver (`routes.yml.j2:24,49`) like every other host, and the GTS
resolver, its EAB secrets and the chain check below are not needed.

Until then, Authelia's `duo_api` stays off. Nothing else in auth/13 or auth/14 depends on it: the
`push.SITE` route change, the shim's enrollment portal, `/provision` and the test push all work
without Authelia calling the Duo API (INFERENCE from the shim's routes, `web.go:56-83`). If the
upstream change stalls, the fallback is the GTS resolver below; a patched Authelia image built
with `github_build` is the other option, at the cost of tracking Authelia releases by hand.

### Duo's pinned bundle (fallback only)

Authelia's release build calls `duoapi.NewDuoApi(ikey, skey, hostname, "")` with no options; only a
`-tags dev` build adds `SetInsecure()`, and no config key changes TLS
(`internal/server/handlers.go:339-352`, `internal/utils/version_{dev,prod}.go`) [AU1]. v0.3.0
defaults to `caPinning: true` and then sets `RootCAs` to the bundle alone (`duoapi.go:224,233-237`)
[DU1]. `SetCAPinning(false)` exists (`:189-197`) but Authelia never calls it.

The bundle (`duoapi.go:515-1003`) holds 15 roots: Amazon Root CA 1-4, Starfield Services G2,
Starfield G2, DigiCert High Assurance EV, DigiCert TLS ECC P384 G5, DigiCert TLS RSA4096 G5,
GlobalSign Root R46 and E46, **GTS Root R2, GTS Root R4**, IdenTrust Commercial Root CA 1 and TLS
ECC CA 2 [DU1]. No ISRG (Let's Encrypt), no GTS R1/R3, no GlobalSign Root CA (R1) or ECC R4.

### Which GTS chains validate

Go stops at the first certificate whose issuer is in `RootCAs` and doesn't fetch AIA [GO1], so what
matters is the intermediate the server sends [GT1]:

| Leaf issuer (as served) | Chains to | Validates against Duo's bundle |
| --- | --- | --- |
| WE1-WE4, the copies **issued by GTS Root R4** | GTS Root R4 | **Yes** (an extra GlobalSign cross-sign is ignored) |
| WE1-WE4, the copies issued by GlobalSign R4 | GlobalSign ECC R4 | No (same keys, so serving the R4-issued copy fixes it) |
| WE5 | GTS Root R3 | No |
| WR1-WR4 | GTS Root R1 | No |
| WR5 | GTS Root R2 | Yes |

The idp-acme session ran the real pinned clients (duo_api_golang v0.3.0 for Authelia,
duo_client_python's `ca_certs.pem` for authentik) against live servers [SH2]:

| Chain served | Pinned Go and Python clients |
| --- | --- |
| GTS ECDSA: leaf → WE1 → GTS Root R4 (cross-signed by GlobalSign Root CA on top) | pass |
| GTS RSA: leaf → WR1-WR4 → GTS Root R1 | fail |
| Let's Encrypt | fail |
| A real Duo API host | pass |

So an `EC256` key from GTS's ACME service should validate, and an RSA key won't. Still
UNVERIFIED for *this* account: which intermediate GTS picks for a given order. Key type alone
doesn't decide it (Google's own EC leaves are issued by WR2 today) [GT1]; the WE1 copy GTS
publishes for AIA download chains to GlobalSign ECC R4, which isn't pinned [SH2]. The `minimal`
profile is documented as "issued using an ECC chain" [GT6]; GTS lists no alternate-chain support
among its ACME divergences [GT7]. Traefik has `keyType`, `profile` and `preferredChain` [TR4].
**So the chain must be checked after the first issuance** (fallback task 3, §11).

### Options

| | (a) Traefik resolver with GTS + EAB | (b) TCP passthrough; the shim terminates TLS |
| --- | --- | --- |
| Who gets the cert | Traefik: EAB supported (`acme.eab.kid`, `acme.eab.hmacEncoded`), any `caServer`, `keyType` `EC256`, `profile`, `preferredChain` [TR4] | Impossible: the shim has no TLS listener at all [SH1] |
| Coexists with LE | Yes: resolvers are a map, each its own account; sharing `/certificates/acme.json` is by design (data keyed by resolver name) [TR5]. HTTP-01 works as for LE (`static.yml.j2:95-101`; HAProxy passes :80 by `Host`, `haproxy.cfg.j2:122-124`) | — |
| Routing | Normal HTTP routers: forward-auth for the portal paths, CrowdSec WAF, access logs | An HTTPS router whose `Host` names the same SNI takes precedence over the TCP router [TR3], so *all* paths bypass Traefik's HTTP middlewares, and the shim's identity routes need forward-auth; no WAF |
| `Host` | `passHostHeader` defaults to `true` [TR2]; the shim checks `lower(Host) == duo-hostname` (shim `internal/duoapi/duoapi.go:98`) | untouched |
| Fixing a bad chain | Only through `profile`/`preferredChain`/re-issue | The shim serves whatever chain file you assemble |
| Verdict | **Fallback** if Authelia's pinning change stalls | Rejected |

Either way Traefik terminates TLS: only the certificate's issuer depends on Authelia. The shim
now requires exactly this: the proxy holds the certificate for `duo-hostname`, from any publicly
trusted issuer, and preserves `Host` [SH1].

Other facts:

- **Hostname and port.** duo_api_golang dials `https://` + hostname and signs `lower(hostname)`
  verbatim, port included (`duoapi.go:55,374-378`) [DU1]; Authelia doesn't parse it [AU1]. A port
  would work only with a matching `duo-hostname` and a dedicated entrypoint. Not needed.
- **SNI**: no `ServerName` is set, so Go uses the URL host (`duoapi.go:229-231`) [DU1];
  `sniStrict` in `tls.yml:10-11` is satisfied.
- **CAA** (fallback): GTS's directory lists `caaIdentities: ["pki.goog"]` [GT4]. If the domain
  has a CAA record, it must allow `pki.goog` (UNVERIFIED whether one exists; public DNS isn't in
  the repo).
- **Limits and lifetime** (fallback): 100 new orders/hour per project [GT5]; leaves ≤ 93 days
  [GT2], so Traefik's default `certificatesDuration: 2160` fits. The GTS account lives in
  `acme.json`, which the secsvcs backup stages with `/etc/opt` (`src/nodes/secsvcs/backup.sh.j2:33`);
  losing it needs a fresh EAB key.

### How Authelia reaches `idp-push.SITE`

- Podman ≥ 4.6 registers an explicitly set `--hostname` as a DNS alias on the network [PD1] [PD2].
  That is how Traefik reaches `http://push.SITE:2586` today (`routes.yml.j2:170-173`,
  `ntfy.container.j2:28`). With ticket 14's `HostName=idp-push.{{ site.url }}`, Authelia would
  resolve `idp-push.SITE` to the shim's container and dial :443 there, bypassing Traefik.
- So pin it to Traefik, as Grafana and Vaultwarden already do for `auth.SITE`:
  `AddHost=idp-push.{{ site.url }}:{{ secsvcs.container_subnet }}.6` in `authelia.container.j2`
  (pattern: `src/services/grafana/grafana.container.j2:33`,
  `src/services/vaultwarden/vaultwarden.container.j2:34-35`). The request then hits Traefik's :443
  with SNI and `Host` `idp-push.SITE`, gets the Let's Encrypt cert (GTS in the fallback), and is
  proxied to
  `http://idp-push.SITE:8080` with `Host` intact.
- `AddHost` stays after Authelia stops pinning: without it Authelia dials the shim's :443, where
  nothing listens.
- Without `AddHost`, Unbound would answer `secsvcs.ip` (`src/services/dns/unbound.conf.j2:36-38`)
  and netavark would hairpin the published :443 to Traefik [PD3], but aardvark's alias answers first
  (INFERENCE).

## 5. Q4: Authelia access rules and header trust

### What the sources say

| Fact | Evidence |
| --- | --- |
| `resources` regexes match the path **and query** (`path.Clean(path) + "?" + rawQuery`) | `access_control_resource.go:36-39`, `types.go:142-152`, `utils/url.go:15-34`; docs: "matches the path and query" [AU6] |
| Rules are first-match; criteria are ANDed | `authorizer.go:55-72`, `access_control_rule.go:58-84` [AU6] |
| A `bypass` rule can't have a `subject` (startup error) | `validator/access_control.go:63-70` [AU9] |
| **Authelia authenticates before evaluating rules, and on `bypass` still returns `Remote-User`/`-Groups`/`-Email`/`-Name` whenever a session exists, including a one-factor session** | `handler_authz.go:202-215`; `handler_authz_util.go:37-40`; `handler_authz_common.go:38-53` (headers set iff username non-empty); `session/user_session.go:59-64` [AU7] |
| A request carrying `Authorization: Basic` is tried as Authelia credentials first; a failure is recorded in regulation even on a bypass rule, and suppresses the Remote-* headers | `schema/server.go:139-150`, `handler_authz.go:303-329`, `handler_authz_authn.go:406-473` [AU8] |
| Authelia sets but never strips Remote-* headers; the proxy must | trusted-header docs [AU11] |
| Traefik forwardAuth deletes every `authResponseHeaders` entry from the request, then copies Authelia's value only if present; a bypass 200 without `Remote-User` reaches the backend with none | `forward.go:314-328` [TR1] |
| Aliases (`Remote_User`, `Remote.User`) aren't covered by that delete, but `aliasHeadersStrategy: delete` drops them at the entrypoint | `forward.go:314-318`, [TR10]; `static.yml.j2:71` |
| A router **without** `authelia@file` forwards a client's `Remote-User` untouched | INFERENCE from [TR1]: only forwardAuth deletes it |
| `headers.customRequestHeaders` with an empty value deletes the request header | Traefik `pkg/middlewares/headers/header.go:128-129` [TR7] |

Consequences:

1. **The bypass leak no longer matters to the shim.** Authelia still hands a one-factor user's
   `Remote-User` to a bypassed route, but the shim's token routes never read the identity header;
   their code, token, passkey or signature is the whole credential (shim `ARCHITECTURE.md`
   "Provisioning"). The `/enroll?code=` page that fell back to the header is gone (`331e7e9`), and
   the identity routes sit behind `two_factor`.
2. **Duo API calls must not pass through `authelia@file`.** They carry
   `Authorization: Basic ikey:sig` (`duoapi.go:97-110`) [DU1], and this repo's forward-auth endpoint
   tries `Authorization: Basic` as an Authelia login (`configuration.yml.j2:116-122`, and Authelia's
   default for `ForwardAuth` [AU8]). Each push would log a failed login for user `DI…`. CrowdSec runs
   the `LePresidente/authelia` collection on Authelia's log (`crowdsec.container.j2:38`,
   `victorialogs.yaml.j2:28-37`), whose brute-force scenario keys on the client IP, here Authelia's
   own container: INFERENCE, a few logins in a row could get Authelia banned from its own Duo
   endpoint. The shim README's single-route Authelia example has this problem (shim follow-up 1).
3. **Split at Traefik by prefix, not in Authelia.** The token family and the Duo API get routers
   without Authelia; everything else on the host goes through `authelia@file` at `two_factor`.
   Traefik never asks Authelia about the public paths, so no `bypass` rules are needed and the
   phone's approve page doesn't depend on Authelia. The non-Authelia routers keep a `strip-remote`
   middleware: the shim's README asks the proxy to strip a client-sent `Remote-User` on every route,
   and it costs nothing.
4. **The shim trusts `Remote-User` only from Traefik's IP**: `trusted-proxies:
   [{{ secsvcs.container_subnet }}.6/32]` (shim `internal/web/web.go:206-210`). Any other
   container on `net.network` that connects directly is refused.

### The shim's paths, by who authenticates

| Path (shim `web.go:56-83`) | Authenticated by | Router (§8) |
| --- | --- | --- |
| `/auth/v2/*` (`ping` unsigned) | HMAC signature, date skew, replay guard (shim `ARCHITECTURE.md` "Duo API facade") | `idp-push-api` |
| `/challenge/{id}`, `/options`, `/assert`, `/fraud` | challenge id + WebAuthn assertion; `Origin` check on POSTs | `idp-push-api` |
| `/challenge/{id}/deny` | deny token in the body | `idp-push-api` |
| `/static/`, `/healthz` | none needed | `idp-push-api` |
| `/token/{code}`, `/token/begin`, `/token/finish` | single-use 5-minute enrollment code, in the path | `idp-push-token`, **no access log** |
| `/token/verify/{device}` (GET form, POST `t=`) | verify token, in the GET query | `idp-push-token`, **no access log** |
| `/token/resend`, `/token/password` | result token in the body | `idp-push-token` |
| `/token/qr` | shim-issued codes only | `idp-push-token` (authentik only; harmless) |
| `/enroll`, `/enroll/begin`, `/enroll/finish`, `/provision`, `/provision/password`, `/devices`, `/devices/{id}/revoke` | identity header from Traefik | `idp-push` (Authelia `two_factor`) |
| anything else | — | `idp-push`: Authelia, then the shim's 404 |

### Authelia rule

Mark the service `admin: true` in the inventory. That puts `idp-push` in `admin_subdomains` and
under the existing rule (`configuration.yml.j2:809-817`): `two_factor` for `authelia_gen_access`
from every network, ahead of the LAN/VPN one-factor rule. No bypass rules. Since Traefik sends only
the identity routes to Authelia, a path-scoped `resources` rule adds nothing.

`networks` matching uses the first `X-Forwarded-For` entry from any peer (`middlewares/wrap.go:37-49`)
[AU10]; Traefik's entrypoints drop forged XFF from untrusted clients (`static.yml.j2:79-81`,
`docs/networking.md:183-190`).

## 6. Q5: reachability

| Endpoint | Reached by | Off the LAN? | Today |
| --- | --- | --- | --- |
| `push.SITE` API and WebSocket | phone apps, browsers, the shim | **Yes**: pushes must arrive anywhere | Public: `push` is a secsvcs subdomain (`src/nodes/secsvcs/inventory.yml:23-24`), so HAProxy routes its SNI (`src/services/haproxy/haproxy.cfg.j2:79-81`) and public DNS points subdomains at the VPS (`docs/networking.md:113-115`) |
| `idp-push.SITE/challenge/*` | the phone's browser, from the notification (shim `ARCHITECTURE.md` "Login") | **Yes**: a login can happen anywhere | Not deployed |
| `idp-push.SITE/enroll`, `/provision`, `/devices` | the person, phone or desktop | Yes, behind `two_factor` from every network | — |
| `idp-push.SITE/token/*` | the phone: setup push, `enroll-link` codes | Yes | — |
| `idp-push.SITE/auth/v2/*` | Authelia only, via `AddHost` | No, but HMAC-signed, so public exposure is safe | — |

Consequences: give the shim `subdomain: idp-push` in the inventory, which adds it to HAProxy's SNI
list, Unbound and Gatus automatically (`src/nodes.jinja:9,54`). Public DNS must resolve
`idp-push.SITE`, which HTTP-01 also needs (UNVERIFIED whether the registrar has a wildcard). Use
`uptime_path: /healthz`.

## 7. Recommendation

| Question | Decision |
| --- | --- |
| Q1 admin header | **Option b.** Delete `ntfy-auth` and Traefik's `NTFY_ADMIN_PASSWORD`. Authelia gates only GET navigations (`Sec-Fetch-Mode: navigate`) on `push.SITE`, minus `/account/token/redeem` and `/file/`. Every other request goes to ntfy unauthenticated by Traefik, as non-browser clients already do. ntfy gets `enable-login: true` and `require-login: true`; people sign in with the account the shim provisions (redeem link, or `/provision/password`). WebSocket requests skip the access log |
| Q2 secrets | Four new secsvcs secrets (§10), plus two GTS EAB secrets only in the fallback. Podman `Secret=…,type=env` for Authelia; mounted secrets plus `NTFY_IDP_PUSH_<KEY>_FILE` for the shim (SIGHUP re-reads them); `render_secrets.sh` for ntfy's `auth-users`/`auth-tokens` (and Traefik's static EAB block in the fallback). Integration key via `AUTHELIA_DUO_API_INTEGRATION_KEY`, not the YAML. No OIDC client (the shim has none) |
| Q3 TLS | **Traefik terminates with the existing `le-http-production` resolver; the shim serves plain HTTP on :8080.** Authelia's `duo_api` is enabled only once an Authelia release skips Duo's CA pinning for non-Duo hosts (upstream request, §4); the rest of auth/13 and auth/14 ships before that. Authelia gets `AddHost=idp-push.SITE:<Traefik .6>`. Fallback if upstream stalls: Option a, a `gts-http-production` resolver (EAB, `keyType: EC256`, HTTP-01), with the served chain checked against Duo's bundle after each issuance |
| Q4 rules and headers | Split the shim's paths at Traefik by prefix. `/token/`, `/challenge/`, `/auth/v2/`, `/static/`, `/healthz`: no Authelia, `strip-remote` middleware, no access log for `/token/`. Everything else: `authelia@file`, Authelia `two_factor` through `admin: true`. **No Authelia `bypass` rules**, and above all no forward-auth on `/auth/v2/`. Shim `trusted-proxies` = Traefik's `.6/32`. No `secure-headers` on the shim: it sets a stricter CSP, HSTS and `nosniff` itself (`web.go:96-97,114`), and `secure-headers` would replace the CSP (cf. `routes.yml.j2:108-110`) |
| Q5 reachability | `push.SITE` stays public. `idp-push.SITE` is public (`subdomain: idp-push`); the Duo API is public too but signed |

## 8. Target state

### Routes

| Host | Router | Rule (abridged) | Middlewares | Authelia | Service |
| --- | --- | --- | --- | --- | --- |
| `push` | `ntfy-ui` | `Method(GET) && Header(Sec-Fetch-Mode, navigate) && !PathPrefix(/file/) && !Path(/account/token/redeem)` | `authelia`, `secure-headers` | `*.SITE` rules: one factor LAN/VPN, two internet | `ntfy` |
| `push` | `ntfy-ws` | `PathRegexp(^/[-_A-Za-z0-9,]+/ws$)`, `accessLogs: false` | — | no | `ntfy` |
| `push` | `ntfy-api` | `Host` only (unchanged) | — | no | `ntfy` |
| `push` | `/metrics` | not routed; :2587 for the scraper only | — | — | — |
| `idp-push` | `idp-push-api` | `PathPrefix(/auth/v2/) \|\| PathPrefix(/challenge/) \|\| PathPrefix(/static/) \|\| Path(/healthz)` | `strip-remote` | no | `ntfy_idp_push` |
| `idp-push` | `idp-push-token` | `PathPrefix(/token/)`, `accessLogs: false` | `strip-remote` | no | `ntfy_idp_push` |
| `idp-push` | `idp-push` | `Host` only | `authelia` | `two_factor` (`admin: true`) | `ntfy_idp_push` |

Rule priority defaults to the rule string's length (`pkg/muxer/http/mux.go:75-77`) [TR8], so both
path routers outrank the `Host`-only catch-all without an explicit `priority`.

### Config sketch

`src/nodes/secsvcs/traefik/routes.yml.j2` (replacing `:96-102`):

```yaml
    # Browser navigations only: Authelia's redirect works there. The web app's fetch, WebSocket
    # and service-worker requests carry ntfy credentials and go to ntfy-api. The redeem landing
    # carries its code in the fragment, which Authelia's post-login redirect would drop.
    ntfy-ui:
      <<: *service
      rule: Host(`push.{{ site.url }}`) && Method(`GET`) && Header(`Sec-Fetch-Mode`, `navigate`) && !PathPrefix(`/file/`) && !Path(`/account/token/redeem`)
      service: ntfy@file
      middlewares:
        - authelia@file
        - secure-headers@file
    # A signed-in web app sends its token as ?auth= on the WebSocket URL
    ntfy-ws:
      <<: *service
      rule: Host(`push.{{ site.url }}`) && PathRegexp(`^/[-_A-Za-z0-9,]+/ws$`)
      service: ntfy@file
      middlewares: []
      observability:
        accessLogs: false
    ntfy-api:
      <<: *service
      rule: Host(`push.{{ site.url }}`)
      service: ntfy@file
      middlewares: []
    # ntfy-idp-push. Token and Duo API routes carry their own credential and skip Authelia (Duo's
    # Basic header would count as a failed Authelia login); they empty the Remote-* headers so a
    # client can't pose as a user. No secure-headers: it would replace the shim's stricter CSP.
    idp-push-api: &idp_push
      rule: Host(`idp-push.{{ site.url }}`) && (PathPrefix(`/auth/v2/`) || PathPrefix(`/challenge/`) || PathPrefix(`/static/`) || Path(`/healthz`))
      entryPoints: websecure
      service: ntfy_idp_push@file
      middlewares:
        - strip-remote@file
      tls:
        options: intermediate@file
        certResolver: le-http-production
    # Enrollment codes in the path, verify tokens in the query
    idp-push-token:
      <<: *idp_push
      rule: Host(`idp-push.{{ site.url }}`) && PathPrefix(`/token/`)
      observability:
        accessLogs: false
    # Identity routes: the shim trusts Remote-User from Traefik's address only
    idp-push:
      <<: *idp_push
      rule: Host(`idp-push.{{ site.url }}`)
      middlewares:
        - authelia@file
  services:
    ntfy_idp_push:
      loadBalancer:
        servers:
          - url: http://idp-push.{{ site.url }}:8080/
```

`src/services/traefik/dynamic/headers.yml.j2` (or `authelia.yml.j2`):

```yaml
    # For routers without authelia@file: forwardAuth is what normally deletes these
    strip-remote:
      headers:
        customRequestHeaders:
          Remote-User: ""
          Remote-Groups: ""
          Remote-Email: ""
          Remote-Name: ""
```

Fallback only (§4): `src/services/traefik/static.yml.j2`, rendered again at start for the EAB
values (fallback task 1, §11), and `certResolver: gts-http-production` on the `idp-push` routers:

```yaml
  # Google Trust Services, for hosts Duo clients call: Duo's pinned bundle has GTS Root R2/R4
  # but no ISRG. EAB keys are single-use; the account then lives in acme.json.
  gts-http-production:
    acme:
      email: {{ site.email }}
      storage: /certificates/acme.json
      caServer: "https://dv.acme-v02.api.pki.goog/directory"
      keyType: EC256
      eab:
        kid: "{% raw %}{{ env('gts_eab_kid') }}{% endraw %}"
        hmacEncoded: "{% raw %}{{ env('gts_eab_hmac') }}{% endraw %}"
      httpChallenge:
        entryPoint: web
```

`src/services/authelia/configuration.yml.j2:342`:

```yaml
# Only once Authelia skips Duo's CA pinning for non-Duo hosts (§4), or with the GTS fallback
duo_api:
  hostname: 'idp-push.{{ site.url }}'
  # integration_key and secret_key: AUTHELIA_DUO_API_INTEGRATION_KEY / _SECRET_KEY env
  enable_self_enrollment: true
```

`src/services/authelia/authelia.container.j2`:

```ini
# The Duo API goes through Traefik, which terminates TLS; aardvark would answer the shim's own IP
AddHost=idp-push.{{ site.url }}:{{ secsvcs.container_subnet }}.6
Secret=duo_integration_key,type=env,target=AUTHELIA_DUO_API_INTEGRATION_KEY
Secret=duo_secret_key,type=env,target=AUTHELIA_DUO_API_SECRET_KEY
```

`src/services/ntfy/config.yml.j2.j2`:

```yaml
auth-users:
  # … existing users …
  - "idp-push:{% raw %}{{ env('ntfy_idp_push_password') | password_hash('bcrypt', env('bcrypt_salt')) }}{% endraw %}:admin"
# auth-access: nothing for idp-push; admins can't have ACL entries
auth-tokens:
  - "alert:{% raw %}{{ env('ntfy_alert_token') }}{% endraw %}:alert"
  - "idp-push:{% raw %}{{ env('ntfy_idp_push_admin_token') }}{% endraw %}:ntfy-idp-push"
enable-login: true
require-login: true
```

Shim quadlet (ticket 14), the parts this research fixes. The image already listens on plain HTTP
:8080 and its healthcheck targets it [SH1]:

```ini
Image=localhost/babraham123/ntfy-idp-push:0.2
HostName=idp-push.{{ site.url }}
# The shim's links and ntfy calls use https://push.SITE, which aardvark would resolve to ntfy:2586
AddHost=push.{{ site.url }}:{{ secsvcs.container_subnet }}.6
Environment=NTFY_IDP_PUSH_TRUSTED_PROXIES={{ secsvcs.container_subnet }}.6/32
# Mounted at /run/secrets/<name>; the shim re-reads *_FILE secrets on SIGHUP
Secret=ntfy_idp_push_admin_token
Secret=duo_secret_key
Environment=NTFY_IDP_PUSH_NTFY_ADMIN_TOKEN_FILE=/run/secrets/ntfy_idp_push_admin_token
Environment=NTFY_IDP_PUSH_DUO_SECRET_KEY_FILE=/run/secrets/duo_secret_key
Secret=duo_integration_key,type=env,target=NTFY_IDP_PUSH_DUO_INTEGRATION_KEY
```

Inventory (`src/nodes/secsvcs/inventory.yml`):

```yaml
  ntfy_idp_push: {subdomain: idp-push, admin: true, uptime: ntfy-idp-push, uptime_path: /healthz,
                  upstream: ghcr.io/babraham123/ntfy-idp-push:0.2}
```

## 9. Acceptance checks, restated for this design

The ticket's `curl` checks hold, reworded for the shim's paths: `/challenge/<id>` (not `/c/<id>`)
and `/token/<code>` (not `/enroll?code=`).

```bash
curl -s https://idp-push.SITE/auth/v2/ping                  # {"time":…}, no redirect
curl -s -o /dev/null -w '%{http_code}\n' https://idp-push.SITE/challenge/x   # 410/404 from the shim
curl -s -o /dev/null -w '%{http_code}\n' https://idp-push.SITE/provision    # 302 to auth.SITE
curl -s -o /dev/null -w '%{http_code}\n' -H 'Remote-User: alice' https://idp-push.SITE/provision  # still 302
curl -s -o /dev/null -w '%{http_code}\n' https://idp-push.SITE/token/x      # 410/404 from the shim
curl -s https://push.SITE/v1/health                         # {"healthy":true}
curl -s -o /dev/null -w '%{http_code}\n' -H 'Sec-Fetch-Mode: navigate' https://push.SITE/  # 302
```

## 10. `secrets_template.yaml` entries

Append to `src/nodes/secsvcs/secrets_template.yaml` (before `...`):

```yaml
# ntfy's admin `idp-push` for ntfy-idp-push; only hashed into auth-users, the shim uses the token
# LC_ALL=C tr -dc 'A-Za-z0-9!#%&()*+,-.:;<=>?[]^_{|}~' </dev/urandom | head -c 20; echo
ntfy_idp_push_password: ""
# sudo podman run --rmi docker.io/binwiederhier/ntfy:latest token generate
ntfy_idp_push_admin_token: ""
# Shared by Authelia's duo_api and ntfy-idp-push. Prints both keys:
# sudo podman run --rm ghcr.io/babraham123/ntfy-idp-push:0.2 keygen
duo_integration_key: ""
duo_secret_key: ""
# Fallback only (auth/13 §4): Google Trust Services ACME EAB for Traefik's gts-http-production
# resolver, while Authelia still pins Duo's CAs. Leave out otherwise. Single use, void
# 7 days after creation if unused; the ACME account then lives in acme.json. A new pair is only
# needed if acme.json loses that account.
# gcloud publicca external-account-keys create   # keyId, b64MacKey
gts_eab_kid: ""
gts_eab_hmac: ""
```

## 11. Follow-up tasks

For ticket 14 (or folded into it):

1. **ntfy:** add `idp-push` (admin) to `auth-users`, its token to `auth-tokens`, both secrets to
   the `render_secrets.sh` list (`ntfy.container.j2:47`); **no** `auth-access` line for it.
   Set `enable-login: true`, `require-login: true`. Optionally exempt the shim's IP from rate
   limits (`visitor-request-limit-exempt-hosts`, `config.yml.j2.j2:306`): its calls arrive through
   Traefik with its own IP in `X-Forwarded-For`.
2. **Traefik `push.SITE`:** replace `routes.yml.j2:96-102` with `ntfy-ui`/`ntfy-ws`/`ntfy-api`
   (§8). Delete `ntfy-auth` (`basic_auth.yml:9-12`) and `traefik.container.j2:32`. Update
   `docs/security.md:107-110` (ntfy leaves the shared-admin list) and the `telemetry` step in
   `docs/guides/secsvcs.md.j2:75`.
3. **Web push cutover:** stop ntfy, remove `/var/cache/ntfy/webpush.db` (`config.yml.j2.j2:197`),
   start it. Browsers re-register under their own login on the next app load (`hooks.js:191-208`)
   [NT6]. Otherwise admin-authorized subscriptions keep delivering for up to 60 days.
4. **People's accounts:** each `telemetry` member provisions their ntfy account at
   `idp-push.SITE/provision` and signs in to the web app; then retire the shared `person` login.
5. **Traefik `idp-push.SITE`:** `strip-remote` middleware, the three routers and the service
   (§8), on `le-http-production`; inventory entry with `subdomain: idp-push`, `admin: true`,
   `uptime_path: /healthz` and `upstream: ghcr.io/babraham123/ntfy-idp-push:0.2`.
6. **Shim container:** mounted secrets with `_FILE` env (§8), no listener or healthcheck
   overrides. Back up with `podman exec ntfy_idp_push ntfy-idp-push backup -` into the stage, as
   `pg_dumpall` is (`backup.sh.j2:20-29`), instead of `stage_volume`.
7. **Authelia, gated on upstream:** `duo_api` block, `AddHost` and the two `Secret=` lines (§8),
   once an Authelia release skips Duo's CA pinning for non-Duo hosts. Leave
   `default_2fa_method: 'totp'`. Until then the shim runs for enrollment and provisioning only.
8. **Upstream request:** the authelia#7647 reply is posted [AU12]; once the maintainer agrees,
   send the PR (`SetCAPinning(isDuoHost(host))`, a startup log line when pinning is off).

Fallback, only if the upstream change stalls:

1. **GTS resolver:** add `gts-http-production` to `static.yml.j2`. Because the static file can't
   be templated by Traefik [TR6], make it `static.yml.j2.j2` and render it in an `ExecStartPre`
   with `render_secrets.sh … gts_eab_kid,gts_eab_hmac` on every node that installs it
   (`src/base/podman/svcs_lib.sh:15`), with empty values on nodes that never use the resolver.
   INFERENCE: Traefik registers the account only when a router first asks the resolver for a
   cert, so empty values elsewhere are harmless; UNVERIFIED.
2. **DNS/CAA:** confirm no CAA record excludes `pki.goog`. (Public DNS for `idp-push.SITE` is
   needed either way.)
3. **Chain check after first issuance:** extract Duo's bundle (`duoapi.go:515-1003`) to a file,
   then `openssl s_client -connect idp-push.SITE:443 -servername idp-push.SITE -showcerts` and
   `openssl verify -CAfile duo.pem -untrusted chain.pem leaf.pem`. It must end at GTS Root R4 (or
   R2). If it ends at R1/R3 or GlobalSign, set `profile: minimal` (or `preferredChain`) and
   re-issue. Re-check after each renewal (shim follow-up 3).

For the ntfy-idp-push repo:

1. **README's Authelia example sends the Duo API through forward-auth:** its single-domain rules
   bypass `^/auth/v2/` in Authelia, so the proxy still calls Authelia with Duo's
   `Authorization: Basic`, which Authelia tries as a login (§5). Recommend excluding `/auth/v2/`
   from the forward-auth route at the proxy instead.
2. **Pinned-CA self-check (fallback only):** a `healthcheck --duo-pinned` mode that calls
   `/auth/v2/ping` through `duo_api_golang` with default pinning, so a renewal that changes the
   chain is caught before a login fails.
3. **Metrics:** still none at v0.2.0; either add a `/metrics` endpoint or keep the scrape job out
   of ticket 14.

Resolved since the first pass: code-flow enrollment is routable by prefix (`/token/*`); the
README and `ARCHITECTURE.md` now warn that the proxy must strip a client-sent identity header on
every route; the image listens on plain HTTP :8080 and its healthcheck targets it.

## 12. Sources

Repo references are inline. Local checkouts: ntfy at `/Users/bereket/Personal/ntfy` (`ebc4a7ba`),
ntfy-idp-push at `/Users/bereket/Personal/ntfy-idp-push` (v0.2.0, `331e7e9`). External:

- [AU1] Authelia v4.39.28, Duo client construction and build tags:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/server/handlers.go#L339-L352>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/utils/version_dev.go>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/utils/version_prod.go>
  - <https://github.com/authelia/authelia/blob/v4.39.28/go.mod#L17>
- [AU2] Authelia `duo_api` schema and validator:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/schema/duo.go#L8-L14>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/validator/duo.go#L14-L38>
- [AU3] Authelia secrets and env sources:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/const.go#L85-L87>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/helpers.go#L17-L23>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/sources.go#L287-L325>
  - <https://www.authelia.com/configuration/methods/secrets/>
- [AU4] Authelia templating, secret env exclusion:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/templates/util.go#L30-L46>
  - <https://www.authelia.com/reference/guides/templating/>
- [AU5] Authelia Duo flows (`preauth`, `auth` only; self-enrollment is UI-only):
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/duo/duo.go>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_sign_duo.go#L160-L192>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/server/template.go#L245-L246>
- [AU6] Authelia access control, resources match path and query, first match:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/authorization/access_control_resource.go#L36-L39>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/authorization/types.go#L142-L152>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/utils/url.go#L15-L34>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/authorization/authorizer.go#L55-L72>
  - <https://www.authelia.com/configuration/security/access-control/#resources>
- [AU7] Authelia authz handler, headers on bypass:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_authz.go#L157-L256>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_authz_util.go#L37-L41>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_authz_common.go#L38-L53>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/session/user_session.go#L59-L64>
- [AU8] Authelia authn strategies and Basic regulation:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/schema/server.go#L139-L150>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_authz.go#L303-L329>
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/handlers/handler_authz_authn.go#L406-L473>
- [AU9] Authelia: bypass with subject rejected:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/configuration/validator/access_control.go#L63-L70>
- [AU10] Authelia client IP from `X-Forwarded-For`:
  - <https://github.com/authelia/authelia/blob/v4.39.28/internal/middlewares/wrap.go#L37-L49>
- [AU11] Authelia trusted header SSO (the proxy must strip):
  - <https://www.authelia.com/integration/trusted-header-sso/introduction/>
- [AU12] authelia#7647, ntfy as a mobile push method (open; reply posted 2026-10-17):
  <https://github.com/authelia/authelia/issues/7647>
- [DU1] duo_api_golang v0.3.0 `duoapi.go` (bundle L515-1003, `NewDuoApi` L219-265, signing L55,
  L97-110, URL L374-378): <https://github.com/duosecurity/duo_api_golang/blob/v0.3.0/duoapi.go>
- [GO1] Go `crypto/x509` chain building: <https://github.com/golang/go/blob/master/src/crypto/x509/verify.go>
- [GT1] Google Trust Services repository (roots, intermediates):
  - <https://pki.goog/repository/>
  - <https://pki.goog/repo/repo.json>
- [GT2] GTS CP/CPS 6.10 (§1.3.1 CAs, §6.1.5 key types, §6.3.2 ≤ 93 days):
  - <https://pki.goog/repo/cp-cps-tls/6.10/GTS-CP-CPS-TLS.md>
- [GT3] Google Cloud Public CA (EAB required, challenges):
  - <https://cloud.google.com/certificate-manager/docs/public-ca>
- [GT4] Public CA tutorial (directories, EAB 7 days and single use, `gcloud` command):
  - <https://cloud.google.com/certificate-manager/docs/public-ca-tutorial>
  - <https://dv.acme-v02.api.pki.goog/directory>
- [GT5] Public CA quotas: <https://cloud.google.com/certificate-manager/docs/quotas>
- [GT6] GTS certificate profiles: <https://developers.google.com/public-key-infrastructure/profiles>
- [GT7] GTS ACME divergences:
  - <https://developers.google.com/public-key-infrastructure/faq/acme-divergences>
- [NT1] ntfy v2.30.0 release: <https://github.com/binwiederhier/ntfy/releases/tag/v2.30.0>
- [NT2] ntfy server routing and auth:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/server/server.go>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/server/server_auth.go>
- [NT3] ntfy web app auth:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/app/Connection.js>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/app/utils.js>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/app/UserManager.js>
- [NT4] ntfy service worker and registration:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/public/sw.js>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/registerSW.js>
- [NT5] ntfy provisioning parsers and token format:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/cmd/serve.go>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/user/util.go>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/user/manager.go>
- [NT6] ntfy web push:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/server/server_webpush.go>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/components/hooks.js>
- [NT7] ntfy login flags:
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/server/server_web.go>
  - <https://github.com/binwiederhier/ntfy/blob/v2.30.0/web/src/components/App.jsx>
- [NT8] ntfy#597, auth details in `ntfy://` links: <https://github.com/binwiederhier/ntfy/issues/597>
- [NT9] ntfy#1596, OIDC for user auth (open): <https://github.com/binwiederhier/ntfy/issues/1596>
- [NT10] ntfy PR #1579, WIP `auth-user-header` (open): <https://github.com/binwiederhier/ntfy/pull/1579>
- [NT11] ntfy PR #1971, header authentication (open): <https://github.com/binwiederhier/ntfy/pull/1971>
- [NT12] ntfy#601, username from a header (open): <https://github.com/binwiederhier/ntfy/issues/601>
- [NT13] ntfy fork, branch `token-enroll-codes`, commits `dc653887` and `ebc4a7ba` (local
  checkout; `server/server.go:110,690,778`, `web/src/app/tokenRedeem.js`)
- [NT14] ntfy PR #2068, one-time enrollment codes (open):
  <https://github.com/binwiederhier/ntfy/pull/2068>
- [PD1] podman-network(1) DNS notes; podman-run(1) `--hostname`:
  - <https://docs.podman.io/en/latest/markdown/podman-network.1.html>
  - <https://docs.podman.io/en/latest/markdown/podman-run.1.html>
- [PD2] libpod hostname alias (from v4.6.0):
  - <https://github.com/containers/podman/blob/main/libpod/networking_common.go>
- [PD3] netavark nftables DNAT and hairpin:
  - <https://github.com/containers/netavark/blob/main/src/firewall/nft.rs>
- [PD4] podman-systemd.unit(5) `Secret=`; podman-run(1) `--secret` (`type=mount` default,
  `/run/secrets/<name>`):
  - <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>
  - <https://docs.podman.io/en/latest/markdown/podman-run.1.html#secret-secret-opt-opt>
- [RFC1] RFC 8555 §7.3.4 External Account Binding, §7.4.2 alternate chains:
  - <https://www.rfc-editor.org/rfc/rfc8555#section-7.3.4>
- [RFC2] RFC 9110 §10.2.2 `Location` (fragment inheritance):
  - <https://www.rfc-editor.org/rfc/rfc9110#section-10.2.2>
- [SH1] ntfy-idp-push v0.2.0 (`331e7e9`): `README.md`, `ARCHITECTURE.md`, `Containerfile`,
  `deploy/server.yml`, `internal/routes/routes.go`, `internal/web/web.go`,
  `internal/config/config.go`, `internal/config/keys.go`, `internal/duoapi/duoapi.go`
  (<https://github.com/babraham123/ntfy-idp-push/tree/v0.2.0>; releases
  <https://github.com/babraham123/ntfy-idp-push/releases>)
- [SH2] Claude Code sessions in `~/Personal/ntfy-idp-push`, 2026-10-14: idp-acme (live test of
  duo_api_golang v0.3.0 and duo_client_python's `ca_certs.pem` against GTS ECDSA, GTS RSA, Let's
  Encrypt and Duo hosts; the `SetCAPinning(isDuoHost(host))` proposal; the drafted
  authelia#7647 reply) and idp-review (the decision to drop ACME and ask Authelia to skip
  pinning). Secondary: re-run the chain test before relying on it
- [TR1] Traefik v3.7.14 forwardAuth header handling:
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/middlewares/auth/forward.go#L314-L344>
- [TR2] Traefik `passHostHeader` default:
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/config/dynamic/http_config.go#L21-L22>
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/proxy/httputil/proxy.go#L133-L136>
- [TR3] Traefik TCP vs HTTPS routing on one entrypoint:
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/server/router/tcp/router.go#L205-L243>
- [TR4] Traefik ACME (EAB, `keyType`, `profile`, `preferredChain`):
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/provider/acme/provider.go#L47-L99>
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/install-configuration/tls/certificate-resolvers/acme.md>
- [TR5] Traefik resolvers and shared storage:
  - <https://github.com/traefik/traefik/blob/v3.7.14/cmd/traefik/traefik.go#L464-L482>
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/provider/acme/local_store.go#L35-L84>
- [TR6] Traefik static config sources are exclusive; templating only in dynamic files:
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/getting-started/configuration-overview.md>
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/routing-configuration/other-providers/file.md>
- [TR7] Traefik headers middleware, empty value deletes:
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/middlewares/headers/header.go#L117-L132>
- [TR8] Traefik rule matchers and priority:
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/routing-configuration/http/routing/rules-and-priority.md>
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/muxer/http/mux.go#L75-L77>
- [TR9] Traefik multi-layer routing:
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/routing-configuration/http/routing/multi-layer-routing.md>
- [TR10] Traefik `aliasHeadersStrategy`:
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/install-configuration/entrypoints.md>
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/security/header-aliases.md>
- [TR11] Traefik HTTP middleware list:
  - <https://github.com/traefik/traefik/blob/v3.7.14/docs/content/reference/routing-configuration/http/middlewares/overview.md>
  - <https://github.com/traefik/traefik/blob/v3.7.14/pkg/config/dynamic/middlewares.go#L350-L352>
- [W1] WHATWG Fetch, HTTP-network-or-cache fetch (default `User-Agent`):
  - <https://fetch.spec.whatwg.org/#http-network-or-cache-fetch>
- [W2] WHATWG WebSockets, establish a WebSocket connection (a fetch; redirect mode "error"):
  - <https://websockets.spec.whatwg.org/#concept-websocket-establish>
- [W3] W3C Fetch Metadata Request Headers (`Sec-Fetch-Mode`, not settable by script):
  - <https://w3c.github.io/webappsec-fetch-metadata/>
- [W4] W3C Service Workers, Update (top-level script redirect mode "error"):
  - <https://w3c.github.io/ServiceWorker/#update-algorithm>
