# 14. Install ntfy-idp-push on secsvcs and wire it to ntfy and Authelia

Status: needs-triage
Type: feature
Repo: homelab
Source: maintainer request 2026-10-14; design in ntfy-idp-push v0.2.0 `README.md` and
`ARCHITECTURE.md` (<https://github.com/babraham123/ntfy-idp-push>)
Blocked by: 13 (credentials, TLS and route decisions); step 5 also on an Authelia release that skips
Duo's CA pinning for non-Duo hostnames (authelia#7647)

## Problem

Authelia's mobile push needs Duo (`duo_api` is commented out at
`src/services/authelia/configuration.yml.j2:342`). `ntfy-idp-push` speaks Duo's Auth API, delivers
the push over the existing ntfy server, and approves only with a WebAuthn assertion from the enrolled
phone. It also provisions per-person ntfy accounts for the web app, which since auth/13 has no
injected admin login. It is not deployed: no quadlet, secrets, routes, ntfy account or Authelia config.

Decisions and config sketches: [13-research-notes.md](13-research-notes.md) §7-§10.

## Scope

1. **Image.** Pulled, not built: `upstream: ghcr.io/babraham123/ntfy-idp-push:0.2` in
   `src/nodes/secsvcs/inventory.yml`, so `image_updater.py` scans it like the other upstream images.
   The image listens on plain HTTP :8080 and its healthcheck targets that.
2. **Quadlet.** `src/services/ntfy_idp_push/ntfy_idp_push.container.j2` on secsvcs: `net.network`,
   next free IP (`{{ secsvcs.container_subnet }}.18` today), `HostName=idp-push.{{ site.url }}`,
   `AddHost=push.{{ site.url }}:<Traefik .6>` (aardvark would otherwise resolve `push.SITE` to ntfy's
   :2586), read-only root, all caps dropped, SQLite on `ntfy_idp_push.volume`. Config
   `src/services/ntfy_idp_push/config.yml.j2`:
   - `duo-hostname: idp-push.{{ site.url }}` (also the WebAuthn RP ID)
   - `ntfy-base-url: https://push.{{ site.url }}`, `ntfy-topic-prefix: push-`
   - `trusted-proxies: [{{ secsvcs.container_subnet }}.6/32]` (Traefik only); `identity-header`
     stays `Remote-User`
   - `enroll-portal-url: https://idp-push.{{ site.url }}/enroll`
   - `enroll-role: user`, `enroll-access` and `default-topics` matching today's `person` grants
     (`hass*:ro`, `chat*:rw`) in `src/services/ntfy/config.yml.j2.j2`
   - Secrets: `Secret=ntfy_idp_push_admin_token` and `Secret=duo_secret_key` mounted at
     `/run/secrets/`, read through `NTFY_IDP_PUSH_NTFY_ADMIN_TOKEN_FILE` and
     `NTFY_IDP_PUSH_DUO_SECRET_KEY_FILE`; `duo_integration_key` as `NTFY_IDP_PUSH_DUO_INTEGRATION_KEY`.
3. **Install and operations.** `ntfy_idp_push)` case in `src/nodes/secsvcs/install_svcs.sh`. In
   `src/nodes/secsvcs/backup.sh.j2`, `podman exec ntfy_idp_push ntfy-idp-push backup -` into the
   stage, like the `pg_dumpall` step: a consistent copy of the passkey database while serving.
   Inventory `uptime: ntfy-idp-push`, `uptime_path: /healthz`. No Prometheus scrape: the shim has no
   metrics endpoint.
4. **ntfy.** In `src/services/ntfy/config.yml.j2.j2`: admin user `idp-push` (new
   `ntfy_idp_push_password`) and an `auth-tokens` entry for `ntfy_idp_push_admin_token`; add both
   secrets to the `render_secrets.sh` list in `src/services/ntfy/ntfy.container.j2`. **No
   `auth-access` entry for `idp-push`**: ntfy refuses to start with ACL entries for an admin.
   `auth-default-access: deny-all` stays. Until ntfy#597 (binwiederhier/ntfy#2068) ships, the shim
   falls back to plain topic links and `/provision/password`.
5. **Authelia (after the upstream pinning change ships).** Uncomment `duo_api` with
   `hostname: idp-push.{{ site.url }}` and `enable_self_enrollment: true` (Authelia then links to
   the shim's `enroll-portal-url`); both keys from env:
   `Secret=duo_integration_key,type=env,target=AUTHELIA_DUO_API_INTEGRATION_KEY` and
   `Secret=duo_secret_key,type=env,target=AUTHELIA_DUO_API_SECRET_KEY` in `authelia.container.j2`,
   plus `AddHost=idp-push.{{ site.url }}:<Traefik .6>` so the Duo calls reach Traefik's TLS, not the
   shim's :8080. Leave `default_2fa_method: 'totp'`. No `access_control` rules beyond `admin: true`
   (step 6).
6. **Traefik and DNS.** Inventory `subdomain: idp-push`, `admin: true` (HAProxy SNI, Unbound,
   Gatus, and Authelia's `two_factor` admin rule). In `src/nodes/secsvcs/traefik/routes.yml.j2`, on
   `le-http-production`:
   - `idp-push-api`: `/auth/v2/`, `/challenge/`, `/static/`, `/healthz`; no Authelia (Duo's
     `Authorization: Basic` would count as a failed Authelia login); `strip-remote`.
   - `idp-push-token`: `/token/`; no Authelia; `strip-remote`; `accessLogs: false` (codes in the
     path, verify tokens in the query).
   - `idp-push`: everything else on the host, `authelia@file`.
   - A `strip-remote` headers middleware that empties `Remote-User`, `-Groups`, `-Email`, `-Name`.
   - No `secure-headers`: the shim sets a stricter CSP, HSTS and `nosniff` itself.
   Public DNS must resolve `idp-push.SITE`.
7. **Docs.** Service catalog entry in `docs/services.md`; "mobile push" in `CONTEXT.md` if the term
   is new; enrollment steps for a person in `docs/maintenance.md` (first enrollment needs another
   Authelia second factor, or an `enroll-link`).

Steps 1-4, 6 and 7 ship before step 5; the shim then serves provisioning and enrollment only.

## Acceptance

- `install_svcs.sh ntfy_idp_push` on secsvcs starts the container healthy; the image passed the scan.
- `curl` from outside the LAN: `idp-push.SITE/auth/v2/ping`, `/challenge/x` and `/token/x` answer
  from the shim without an Authelia redirect; `/provision` redirects to Authelia, also with a forged
  `Remote-User` header.
- A person provisions their ntfy account at `/provision` and signs in to the ntfy app and web app.
- A person enrolls a phone from `/enroll` after a `two_factor` login; the ntfy app on the phone
  subscribes to its `push-<uuid>` topic; the test push arrives. An `enroll-link` code enrolls too.
- After step 5: Authelia starts with `duo_api` enabled (release image, no dev flags). Authelia login
  with "Mobile Push": the notification arrives, Approve plus the phone's passkey completes the login;
  Deny and a 60 s timeout both fail it.
- Anonymous `GET push.{{ site.url }}/push-<uuid>/json` is refused; only `idp-push` can publish to
  `push-*`.
- `ntfy-idp-push device revoke <id>` makes the next login on that phone fail.
- Backups contain the shim's database copy.

## Comments

- 2026-10-17 agent: rewritten for ntfy-idp-push v0.2.0 and auth/13's research: pulled image, HTTP
  only, forward-auth only, `/token/` and `/challenge/` routes, secret files, `backup`, no metrics;
  Authelia's `duo_api` split out behind the upstream pinning change.
