# 02. Gate VictoriaMetrics/VictoriaLogs/Alertmanager/ntfy UIs on a telemetry LDAP group

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 13

## Problem

`src/secsvcs/traefik/basic_auth.yml` injects `admin:$X_ADMIN_PASSWORD` for anyone who
clears Authelia, so every authenticated user is admin on those four tools.

## Mechanism: Traefik multi-layer routing (confirmed)

Traefik's multi-layer routing
(<https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/multi-layer-routing/>)
does exactly this. A **parent** router matches `Host()`, runs its middlewares
(`authelia@file` ForwardAuth), and Traefik then evaluates **child** routers — declared
with `parentRefs: [parent]` — against the request *as modified by the parent's
middlewares*. ForwardAuth copies `authResponseHeaders` (already includes `Remote-Groups`
in `src/traefik/dynamic/authelia.yml.j2`) onto the request, so a child rule
`HeaderRegexp(\`Remote-Groups\`, ...)` sees Authelia's verdict. Documented order:
parent rule → parent middlewares → one child matches. Constraints: file provider only
(fine), parents must have no `service`, `entryPoints`, `tls` or `observability`; those
move to the children. Requires Traefik ≥ v3.6 (you run v3.7 — verify the `parentRefs`
key exists in that version's reference).

Spoofing note: ForwardAuth strips the listed `authResponseHeaders` from the incoming
request before setting them from Authelia's response, so a client-supplied
`Remote-Groups` cannot pass the child rule. Confirm on your version.

## Change

- LLDAP group `telemetry` (human step); add yourself.
- `src/secsvcs/traefik/routes.yml.j2`, for each of `metrics`, `logs`, `alert`, `push`
  (replacing today's `-ui` router; keep the `-api`/`-hass-api` routers untouched):

  ```yaml
  victoriametrics-ui:                       # parent: authenticate
    rule: Host(`metrics.{{ site.url }}`) && HeaderRegexp(`User-Agent`, `^Mozilla\/.*`)
    middlewares: [authelia@file]
  victoriametrics-ui-telemetry:             # child: authorised group → app, with admin header
    parentRefs: [victoriametrics-ui]
    rule: HeaderRegexp(`Remote-Groups`, `(^|,)telemetry(,|$)`)
    service: victoriametrics@file
    middlewares: [vm-auth@file, secure-headers@file]
    entryPoints: websecure
    tls: {options: intermediate@file, certResolver: le-http-production}
  victoriametrics-ui-denied:                # child: everyone else
    parentRefs: [victoriametrics-ui]
    rule: PathPrefix(`/`)
    priority: 1
    service: forbidden@file                 # nginx 403 page on websvcs, or a tiny static responder on secsvcs
    entryPoints: websecure
    tls: {options: intermediate@file, certResolver: le-http-production}
  ```

  Check the exact separator Authelia uses in `Remote-Groups` (comma vs comma-space) and
  adjust the regex. Without a `-denied` child, a non-member gets Traefik's 404, which is
  acceptable but less clear.
- The shared `&service` anchor in `routes.yml` sets `entryPoints`/`tls` on every router;
  parents must not have them, so give parents their own anchor.
- Optional belt-and-braces: an Authelia `access_control` rule for the same domains with
  `subject: group:telemetry`. Not required once Traefik enforces it; skip unless you want
  the denial to land on Authelia's portal instead of a 403.
- Later, per-app real roles instead of a shared admin header (Grafana already maps OIDC
  groups; VictoriaMetrics via `vmauth`). Out of scope.

## Acceptance

- A user in `authelia_gen_access` but not `telemetry` gets 403 on `metrics.SITE` UI;
  a `telemetry` member gets the UI with the injected admin basic-auth.
- `curl -H 'Remote-Groups: telemetry'` without a session still lands on the Authelia
  redirect (spoof check).
- HA → `metrics.SITE` with `Authorization: Token` (the `-hass-api` router) is unaffected.

## Comments
