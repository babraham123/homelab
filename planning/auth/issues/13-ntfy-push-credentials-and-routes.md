# 13. Research: credentials for ntfy and ntfy-idp-push, and which routes Authelia protects

Status: ready-for-agent
Type: research
Repo: homelab
Source: maintainer request 2026-10-14; design in `~/Personal/ntfy-idp-push/PLAN.md`

## Problem

`ntfy-idp-push` (a Duo Auth API drop-in that delivers Authelia mobile push over ntfy, approvals bound
by WebAuthn) will run on secsvcs next to Authelia and ntfy. Before it is deployed, two things need an
answer:

1. **How credentials reach ntfy and the shim.** Today ntfy gets `ntfy_*_password` podman secrets
   rendered into `auth-users` via `render_secrets.sh` (`src/services/ntfy/ntfy.container.j2`), and
   Traefik gets `ntfy_admin_password` (`src/nodes/secsvcs/traefik/traefik.container.j2:32`). The
   shim will need: an ntfy **admin token** (user/ACL API, enrollment codes), the Duo
   integration/secret key pair shared with Authelia's `duo_api` block
   (`src/services/authelia/configuration.yml.j2:342`, currently commented out), an OIDC client secret
   if `auth-mode: oidc` is used, and ACME EAB credentials for a Google Trust Services certificate
   (Authelia pins Duo's CAs; Let's Encrypt is not in the bundle).
2. **Which routes Authelia must protect.** The `ntfy-ui` router
   (`src/nodes/secsvcs/traefik/routes.yml.j2:96-97`) matches every `Mozilla/*` User-Agent on
   `push.SITE`, runs `authelia@file`, then `ntfy-auth@file` injects
   `Authorization: Basic admin:$NTFY_ADMIN_PASSWORD` (`src/nodes/secsvcs/traefik/basic_auth.yml:9-12`).
   Any Authelia-authenticated browser user is therefore ntfy **admin** for every API call the web app
   makes, and the header overwrites the Bearer token the web app would send after signing in. The
   shim's per-user model (ntfy username == Authelia username, `enroll-access` grants, device-scoped
   `push-*` topics) cannot coexist with that injection.

## Questions

- Replace the admin-header injection: can Traefik map `Remote-User` from Authelia to a per-user ntfy
  credential, or should browser sessions sign in to ntfy via the enrollment-code redeem route
  (ntfy#597 web counterpart) and send their own Bearer token, with Authelia only gating the UI shell?
- Secret plumbing for the shim: one `ntfy_idp_push_admin_token` provisioned in ntfy `auth-tokens`
  (admin user `idp-push`), `duo_integration_key` + `duo_secret_key` shared by Authelia (as
  `AUTHELIA_DUO_API_SECRET_KEY`) and the shim, `gts_eab_kid` + `gts_eab_hmac`. Add to
  `src/nodes/secsvcs/secrets_template.yaml` with generation commands, following the `ntfy_alert_token`
  pattern.
- TLS: the Duo API routes must present a cert chaining to a CA in Duo's pinned bundle. Decide between
  the shim terminating TLS itself on a dedicated hostname/IP (bypassing Traefik's LE resolver) and a
  Traefik router with a GTS-issued cert (`certResolver` with EAB). The Duo client signs the configured
  hostname, so Traefik must not rewrite `Host`.
- Authelia access rule for the shim's user-facing paths (`two_factor` for enrollment per auth/01's
  reasoning: a password-only attacker must not enroll a phone).

## Route protection matrix (target state)

| Host / path | Authelia forward-auth | Why |
| --- | --- | --- |
| `push.SITE/` web UI shell (Mozilla UA, HTML) | yes | gate the SPA; drop the admin header injection |
| `push.SITE/v1/*`, `/<topic>/{json,sse,ws,…}`, `/file/*` | no | apps and the SPA authenticate with ntfy tokens; ntfy `auth-default-access: deny-all` enforces |
| `push.SITE/account/token/redeem` (SPA route) | no | reached from the QR/deep link on a phone or fresh browser; the code is the proof |
| `push.SITE/metrics` (port 2587) | n/a | internal only, Prometheus scrape |
| `idp-push.SITE/auth/v2/*`, `/frame/qr` | **no** | called by Authelia/authentik server-side with HMAC-signed requests; pinned-CA cert required |
| `idp-push.SITE/c/*` (approve page, deny callback) | **no** | opened from the phone's ntfy notification; WebAuthn is the authentication |
| `idp-push.SITE/enroll?code=…` (admin/IdP-issued link) | no | single-use code is the proof |
| `idp-push.SITE/enroll`, `/provision`, `/devices` | **yes**, `two_factor` | identity via `Remote-User`; shim accepts it only from `trusted-proxies` |
| `idp-push.SITE/metrics` | n/a | internal only |

## Acceptance

- A written decision (comment on this ticket or an ADR under `docs/adr/`) on both questions, with the
  secrets added to `secrets_template.yaml` and the Traefik routers/middlewares for `push.SITE` and
  `idp-push.SITE` changed to match the matrix.
- The `ntfy-auth@file` admin-header injection is gone or scoped so that no ordinary user acts as ntfy
  admin.
- `curl` from the LAN: `idp-push.SITE/auth/v2/ping` and `/c/<id>` answer without an Authelia redirect;
  `/provision` redirects to Authelia; `push.SITE/v1/health` answers without a redirect.

## Comments
