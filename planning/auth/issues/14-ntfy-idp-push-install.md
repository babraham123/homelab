# 14. Install ntfy-idp-push on secsvcs and wire it to ntfy and Authelia

Status: needs-triage
Type: feature
Repo: homelab
Source: maintainer request 2026-10-14; design in `~/Personal/ntfy-idp-push/PLAN.md`
Blocked by: auth/13 (credentials, TLS and route decisions); ntfy-idp-push milestone 7 (container
image, deployable)

## Problem

Authelia's mobile push needs Duo (`duo_api` is commented out at
`src/services/authelia/configuration.yml.j2:342`). `ntfy-idp-push` speaks Duo's Auth API, delivers
the push over the existing ntfy server, and approves only with a WebAuthn assertion from the enrolled
phone. It is not deployed: no image, quadlet, secrets, routes, ntfy account or Authelia config.

## Scope

1. **Image.** `src/services/ntfy_idp_push/build.sh` builds `localhost/ntfy_idp_push` from
   `babraham123/ntfy-idp-push` with `github_build`, as `src/services/finance_exporter/build.sh` does,
   so `image_updater.py` scans it before it replaces the running image.
2. **Quadlet.** `src/services/ntfy_idp_push/ntfy_idp_push.container.j2` on secsvcs: `net.network`,
   next free IP (`{{ secsvcs.container_subnet }}.18` today), `HostName=idp-push.{{ site.url }}`,
   read-only root, all caps dropped, healthcheck on `/auth/v2/ping`, SQLite on
   `ntfy_idp_push.volume`. Config `src/services/ntfy_idp_push/config.yml.j2` (keys from PLAN.md §8):
   - `duo-hostname: idp-push.{{ site.url }}`
   - `ntfy-base-url: https://push.{{ site.url }}`, `ntfy-topic-prefix: push-`
   - `auth-mode: forward`, `trusted-proxies:` Traefik's container IP
   - `enroll-portal-url: https://idp-push.{{ site.url }}/enroll`
   - `enroll-role: user`, `enroll-access` and `default-topics` matching today's `person` grants
     (`hass*:ro`, `chat*:rw`) in `src/services/ntfy/config.yml.j2.j2`
   - `tls-mode` per auth/13's TLS decision
   - Secrets as `NTFY_IDP_PUSH_*` env: `ntfy_idp_push_admin_token`, `duo_integration_key`,
     `duo_secret_key`, and `gts_eab_kid` + `gts_eab_hmac` if the shim terminates TLS.
3. **Install.** `ntfy_idp_push)` case in `src/nodes/secsvcs/install_svcs.sh`; `stage_volume
   ntfy_idp_push` in `src/nodes/secsvcs/backup.sh.j2` (SQLite under a running process, same caveat
   as ntfydb); scrape job in `src/nodes/secsvcs/prometheus.yml.j2`; Gatus check on `/auth/v2/ping`.
4. **ntfy.** In `src/services/ntfy/config.yml.j2.j2`: admin user `idp-push` (new
   `ntfy_idp_push_password`), `auth-tokens` entry for `ntfy_idp_push_admin_token`, `auth-access`
   `idp-push:push-*:wo`; add both secrets to the `render_secrets.sh` list in
   `src/services/ntfy/ntfy.container.j2`. `auth-default-access: deny-all` stays. Enrollment codes
   need an ntfy build with ntfy#597; until then the shim's no-code fallback applies (PLAN.md §6).
5. **Authelia.** Uncomment `duo_api` with `hostname: idp-push.{{ site.url }}`, `integration_key`
   from config, `secret_key` via `Secret=duo_secret_key,type=env,target=AUTHELIA_DUO_API_SECRET_KEY`
   in `authelia.container.j2`, `enable_self_enrollment: true` (Authelia then links to the shim's
   `enroll-portal-url`). Leave `default_2fa_method: 'totp'`. `access_control` rules for
   `idp-push.{{ site.url }}`: `bypass` for `^/auth/v2/`, `^/frame/qr`, `^/c/`, `^/enroll\?code=`;
   `two_factor` for `/enroll`, `/provision`, `/devices`; deny the rest.
6. **Traefik and DNS.** Router(s) for `idp-push.{{ site.url }}` in
   `src/nodes/secsvcs/traefik/routes.yml.j2` per auth/13's matrix (or TCP passthrough if the shim
   terminates TLS); Authelia must resolve `idp-push.{{ site.url }}` to an endpoint presenting the
   GTS-chained cert, without `Host` rewriting.
7. **Docs.** Service catalog entry in `docs/services.md`; "mobile push" in `CONTEXT.md` if the term
   is new; enrollment steps for a person in `docs/maintenance.md`.

## Acceptance

- `install_svcs.sh ntfy_idp_push` on secsvcs starts the container healthy; the image passed the scan.
- Authelia starts with `duo_api` enabled (release image, Duo CA pinning in force, no dev flags).
- A person enrolls a phone from `/enroll` after a `two_factor` login; the ntfy app on the phone
  subscribes to its `push-<uuid>` topic; the test push arrives.
- Authelia login with "Mobile Push": the notification arrives, Approve plus the phone's passkey
  completes the login; Deny and a 60 s timeout both fail it.
- Anonymous `GET push.{{ site.url }}/push-<uuid>/json` is refused; only `idp-push` can publish to
  `push-*`.
- `ntfy-idp-push device revoke <id>` makes the next login on that phone fail.
- Backups contain the shim's database; Prometheus scrapes its metrics.

## Comments
