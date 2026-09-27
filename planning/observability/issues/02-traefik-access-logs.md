# 02. Enable Traefik access logs and ship them to VictoriaLogs

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 19

## Do Traefik access logs add anything over HAProxy logs? (answer)

Yes, and it is not marginal. HAProxy runs the `:443` frontend in **TCP mode** and never
terminates TLS, so its log line has the source IP, SNI, byte counts and timings — no
method, path, status code, user agent, or user. Only `:80` gets HTTP-mode logs, and
that carries just redirects and ACME challenges. Traefik is the only component that
sees decrypted HTTP, and it also sees `Remote-User` from Authelia. Second, **internal
clients never touch HAProxy** (split-horizon DNS), so today there is *no record at
all* of LAN-side requests. Traefik logs are the only request-level and the only
LAN-side record you can have.

## Storage estimate

Inputs: a Traefik JSON access-log line is ~700–1000 B with request headers dropped
(several KB if `headers.defaultMode: keep`, as in the commented-out block today — don't).
Traffic that actually passes through Traefik: Gatus 16 endpoints × 144/day ≈ 2.3k
(≈5k after observability/07), human browsing ≈ 2–5k, Homepage widget polling while the
dashboard is open ≈ 10–30k, internet scanners falling through HAProxy to websvcs ≈
5–50k. vmagent scrapes hit service ports directly and never appear. Ballpark
**20k–100k lines/day across all three proxies → 16–80 MB/day raw.**

- On-node: journald compresses ~3–5× → 5–25 MB/day, and `SystemMaxUse` (default 10 %
  of `/var/log`'s filesystem, capped at 4 GiB) bounds it regardless.
- VictoriaLogs compresses ~10–20× → 1–8 MB/day; at `retention.log_days: 14` that is
  **≈15–110 MB total**. Even a sustained 1M req/day scan is ≈1 GB for the retention
  window.

Verdict: negligible next to the VM disks; the bound is `retention.log_days`, not the
logs. **Approved.**

## Change

- `src/traefik/static.yml.j2`: uncomment `accessLog`, use `format: json`, keep the
  `Authorization: redact` field rule already written, set `headers.defaultMode: drop`
  with `names: {User-Agent: keep, Referer: keep, Remote-User: keep}` and
  `Cookie: drop`, `bufferingSize: 100`. Start unfiltered; add
  `filters.statusCodes: ["400-599"]` later only if the estimate above proves low.
- Check `SystemMaxUse=` in `/etc/systemd/journald.conf` on each container VM and pin it
  (e.g. `1G`) in `src/debian/` so on-node retention is explicit.
- Log to stdout (default) so Fluent Bit's journald tailer picks it up with no extra
  volume. Add a `journald.lua`/parser rule so JSON fields become VictoriaLogs fields.
- Grafana: a VictoriaLogs panel per node filtering `_stream: {unit="traefik.service"}`.

## Acceptance

- `logs.SITE` shows a Traefik request with `RequestPath`, `DownstreamStatus`,
  `request_User-Agent`, and `Remote-User` populated.

## Comments

- 2026-09-26: redact the `access_token` query parameter before logs are stored.
  Vaultwarden's websocket (`/notifications/hub?access_token=<JWT>`) puts a live session
  token in the URL; see vaultwarden/01. If Traefik can't redact a single parameter, drop
  the query string for `vault.SITE` in the fluent-bit pipeline.
