# 13. Research: credentials for ntfy and ntfy-idp-push, and which routes Authelia protects

Status: resolved
Type: research
Repo: homelab
Source: maintainer request 2026-10-14; design in ntfy-idp-push v0.2.0 `README.md` and
  `ARCHITECTURE.md` (<https://github.com/babraham123/ntfy-idp-push>)
Research: [research-13.md](../research-13.md)

## Problem

`ntfy-idp-push` (a Duo Auth API drop-in that delivers Authelia mobile push over ntfy, approvals bound
by WebAuthn) will run on secsvcs next to Authelia and ntfy. Before it is deployed, two things need an
answer:

1. **How credentials reach ntfy, the shim and Authelia.** Today ntfy gets `ntfy_*_password` podman
   secrets rendered into `auth-users` via `render_secrets.sh` (`src/services/ntfy/ntfy.container.j2`),
   and Traefik gets `ntfy_admin_password` (`src/nodes/secsvcs/traefik/traefik.container.j2:32`). The
   shim needs an ntfy **admin token** (user/ACL API, enrollment codes) and the Duo integration/secret
   key pair it shares with Authelia's `duo_api` block (`src/services/authelia/configuration.yml.j2:342`,
   currently commented out). It has no TLS or OIDC of its own: the proxy terminates TLS and signs
   users in with forward-auth. Authelia's Duo client pins Duo's CA bundle, which has no Let's
   Encrypt root, so either Authelia skips pinning for non-Duo hosts (requested upstream,
   authelia#7647) or Traefik needs a Google Trust Services ECDSA cert with ACME EAB credentials.
2. **Which routes Authelia must protect.** The `ntfy-ui` router
   (`src/nodes/secsvcs/traefik/routes.yml.j2:96-97`) matches every `Mozilla/*` User-Agent on
   `push.SITE` except `/file/`, runs Authelia, and sends `telemetry` group members on with
   `Authorization: Basic admin:$NTFY_ADMIN_PASSWORD` injected by `ntfy-auth@file`
   (`src/nodes/secsvcs/traefik/basic_auth.yml:9-12`); everyone else gets a 403 page. So every API
   call a `telemetry` member's browser makes runs as ntfy **admin**, the header overwrites the Bearer
   token the web app would send after signing in, and nobody else can use the web app. The shim's
   per-user model (ntfy username == Authelia username, `enroll-access` grants, device-scoped `push-*`
   topics) can't coexist with that injection.

## Questions

- Replace the admin-header injection: can Traefik map `Remote-User` from Authelia to a per-user ntfy
  credential, or should browser sessions sign in to ntfy themselves (login page, or the ntfy#597
  redeem route the shim's `/provision` links to) and send their own Bearer token, with Authelia only
  gating the UI shell?
- Secret plumbing: `ntfy_idp_push_admin_token` provisioned in ntfy `auth-tokens` (admin user
  `idp-push`), `duo_integration_key` + `duo_secret_key` shared by Authelia and the shim. Add to
  `src/nodes/secsvcs/secrets_template.yaml` with generation commands, following the
  `ntfy_alert_token` pattern.
- TLS: wait for Authelia to skip pinning and use the existing Let's Encrypt resolver, or add a GTS
  resolver (`certResolver` with EAB) now. Either way Traefik terminates TLS; the Duo client signs the
  configured hostname, so Traefik must not rewrite `Host`.
- Authelia access rules for the shim's identity routes (`two_factor` per auth/01's reasoning: a
  password-only attacker must not enroll a phone), and how a client-sent `Remote-User` is kept from
  reaching the shim.

## Route protection matrix (target state)

| Host / path | Authelia forward-auth | Why |
| --- | --- | --- |
| `push.SITE/` web UI page loads (`Sec-Fetch-Mode: navigate`) | yes | gate the SPA; no admin header |
| `push.SITE/v1/*`, `/<topic>/{json,sse,ws,…}`, publish, `/file/*`, SPA assets, `sw.js` | no | apps and the SPA authenticate with ntfy tokens; ntfy `auth-default-access: deny-all` enforces |
| `push.SITE/account/token/redeem` (SPA route) | no | reached from the QR/deep link on a phone or fresh browser; the code, in the fragment, is the proof |
| `push.SITE/metrics` (port 2587) | n/a | internal only, Prometheus scrape |
| `idp-push.SITE/auth/v2/*` | **no** | called by Authelia server-side with HMAC-signed requests; Duo's `Authorization: Basic` must not reach Authelia's forward-auth |
| `idp-push.SITE/challenge/*` (approve page, deny, fraud) | **no** | opened from the phone's ntfy notification; WebAuthn or the deny token is the authentication |
| `idp-push.SITE/token/*` (enrollment codes, setup verify, resend, password, QR) | **no** | the code or token is the proof; no access log, since codes sit in the path and query |
| `idp-push.SITE/static/`, `/healthz` | no | page assets; uptime check |
| `idp-push.SITE/enroll`, `/provision`, `/devices` and their POSTs | **yes**, `two_factor` | identity via `Remote-User`; the shim accepts it only from Traefik's address |

Routes that skip Authelia empty the `Remote-*` headers, so a client can't pose as a user.

## Acceptance

- A written decision (comment on this ticket or an ADR under `docs/adr/`) on all four questions, with
  the secrets added to `secrets_template.yaml` and the Traefik routers/middlewares for `push.SITE`
  changed to match the matrix. The `idp-push.SITE` routers ship with auth/14.
- The `ntfy-auth@file` admin-header injection is gone, so no ordinary user acts as ntfy admin.
- `curl` from the LAN: `push.SITE/v1/health` answers without a redirect; a request with
  `Sec-Fetch-Mode: navigate` to `push.SITE/` redirects to Authelia.

## Answer

Full reasoning and sources: [research-13.md](../research-13.md) §7. Implemented in 11c348c.

- **Admin header:** gone. Traefik can't map `Remote-User` to a per-user ntfy credential, and ntfy
  has no header auth, so browsers sign in to ntfy themselves. Authelia gates only `GET`
  navigations on `push.SITE` (`ntfy-ui`), minus `/file/` and `/account/token/redeem`; every other
  request goes straight to ntfy (`ntfy-api`), and `ntfy-ws` keeps WebSocket requests out of the
  access log because the token rides in `?auth=`. ntfy has `enable-login` and `require-login`;
  its `admin` user stays as a break-glass login. ntfy is no longer behind the `telemetry` group.
- **Secrets:** `ntfy_idp_push_password`, `ntfy_idp_push_admin_token`, `duo_integration_key` and
  `duo_secret_key` in `src/nodes/secsvcs/secrets_template.yaml`. Authelia reads both Duo keys from
  env; the shim mounts its token and secret key as files (`NTFY_IDP_PUSH_<KEY>_FILE`).
- **TLS:** Traefik terminates TLS on `le-http-production`; the shim serves plain HTTP :8080.
  Authelia's `duo_api` waits for an Authelia release that skips Duo's CA pinning for non-Duo hosts
  (authelia#7647). Fallback if that stalls: a GTS resolver with `EC256`.
- **Rules and headers:** `idp-push.SITE` is split at Traefik by path prefix, not with Authelia
  `bypass` rules. The token family (`/token/`, `/challenge/`), the Duo API (`/auth/v2/`),
  `/static/` and `/healthz` skip Authelia and have `Remote-*` emptied; the identity routes go
  through Authelia at `two_factor` via `admin: true`. The shim trusts the identity header only from
  Traefik's `.6/32`. `idp-push` is a public subdomain, like `push`.

Deploy steps (fill the new secrets, delete `/var/opt/ntfy/webpush.db` while ntfy is stopped, the
`curl` checks) travel with auth/14 and the apply notes; the `idp-push.SITE` routers ship with
auth/14.

## Comments

- 2026-10-17 agent: research done, in [research-13.md](../research-13.md) §7.
  - **Admin header:** delete `ntfy-auth` and Traefik's `NTFY_ADMIN_PASSWORD`. Authelia gates only
    `GET` navigations on `push.SITE`, minus `/account/token/redeem` and `/file/`; everything else
    goes straight to ntfy. ntfy gets `enable-login: true` and `require-login: true`; people sign in
    with the account the shim provisions. WebSocket requests skip the access log (`?auth=` carries
    the token). Clear web-push subscriptions at cutover. Traefik can't map `Remote-User` to a
    per-user credential, and ntfy has no header auth in any release.
  - **Secrets:** four new secsvcs secrets: `ntfy_idp_push_password`, `ntfy_idp_push_admin_token`,
    `duo_integration_key`, `duo_secret_key`. Authelia reads both Duo keys from env; the shim mounts
    its token and secret key as files (`NTFY_IDP_PUSH_<KEY>_FILE`). GTS EAB secrets only in the
    fallback.
  - **TLS:** Traefik terminates TLS with `le-http-production`; the shim serves plain HTTP :8080.
    Authelia's `duo_api` waits for an Authelia release that skips pinning for non-Duo hosts (reply
    posted on authelia#7647 2026-10-17). Fallback if that stalls: a GTS resolver with `EC256`, the
    chain checked against Duo's bundle after each issuance.
  - **Rules and headers:** split `idp-push.SITE` at Traefik by prefix, not with Authelia `bypass`
    rules: the token family and Duo API skip Authelia and empty `Remote-*`; the rest goes through
    Authelia at `two_factor` via `admin: true`. The shim's `trusted-proxies` is Traefik's `.6/32`.
  - **Reachability:** `idp-push` is a public subdomain, like `push`; phones approve from anywhere.
- 2026-10-17 agent: implemented. `ntfy-auth` and Traefik's `NTFY_ADMIN_PASSWORD` are gone;
  `ntfy-ui` matches `GET` navigations only, `ntfy-ws` skips the access log; ntfy has
  `enable-login` and `require-login`; the four secrets are in `secrets_template.yaml`; docs no
  longer list ntfy under `telemetry`. ntfy's `admin` user stays as a break-glass login. Left for a
  human at deploy: fill the new secrets, delete `/var/opt/ntfy/webpush.db` while ntfy is stopped
  (subscriptions registered as `admin`), and the `curl` checks. Until auth/14 ships, the web app
  signs in as `person` or `admin`.
- 2026-10-17: resolved; the decisions are in the Answer. The deploy and `curl` checks move to
  auth/14 and the apply notes.
