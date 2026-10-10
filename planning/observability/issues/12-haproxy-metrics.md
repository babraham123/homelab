# 12. Expose HAProxy's metrics on loopback, scrape them, alert and graph

Status: resolved
Type: task
Blocked by: 08
Repo: homelab
Source: split from observability/04 (2026-09-27)

## Problem

HAProxy is the only public ingress and has no metrics. Nobody can see how much the edge
drops, or whether the VPS can reach the service VMs. observability/04 settled the design;
this ticket is its HAProxy half. The VPS vmagent that scrapes it is observability/08.

## Change

1. **Exporter.** Add to `src/services/haproxy/haproxy.cfg.j2`:
   ```
   frontend prometheus
       mode http
       bind 127.0.0.1:8405
       http-request use-service prometheus-exporter if { path /metrics }
       http-request deny
       no log
   ```
   First confirm the build has it: `haproxy -vv | grep -i prometheus` (Debian trixie's
   3.0.x is built with `USE_PROMEX=1`).
2. **Scrape job.** Add `haproxy` to `src/nodes/vpnsvcs/prometheus.yml.j2` (created by 08):
   target `127.0.0.1:8405`, with `instance` relabelled to `vpnsvcs.SITE:8405`.
3. **No `check` on the backend servers.** Maintainer decision: each backend has one
   server, so a health check buys no failover, and a false DOWN would cut traffic.
   Detect an unreachable VM from connection errors instead.
4. **Alerts** in `src/services/vmalert/configs/vps.yml` (created by 08):
   - `HaproxyDown`: `up{job="haproxy"} == 0` for 2m;
   - `HaproxyBackendConnectErrors`:
     `sum by (proxy) (rate(haproxy_backend_connection_errors_total{proxy=~".*svcs_https?_proxy"}[5m])) > 0`
     for 5m. Confirm the metric name against the live `/metrics` output first.
5. **Dashboard.** Import Grafana.com 12693 as `src/services/grafana/dashboards/haproxy.json` and
   fix its datasource.
   - Graph drops with
     `sum by (proxy) (rate(haproxy_frontend_requests_denied_total[5m]))` and
     `haproxy_backend_requests_denied_total{proxy=~"silent_drop_.*"}`.
     `haproxy_frontend_denied_connections_total` stays near 0 here: silent-drop counts
     as a denied request.
   - Remove or fix panels built on `haproxy_backend_up`, which the built-in exporter
     doesn't have.
6. **Docs.**
   - `docs/services.md`: the VPS row and the observability diagram.
   - A new ADR at the next free number: "VPS metrics pushed by a local vmagent".

## Acceptance

- `curl -s 127.0.0.1:8405/metrics | head` works on the VPS, and `ss -ltnp` shows 8405
  bound to `127.0.0.1` only.
- `up{job="haproxy",host="vpnsvcs.SITE"} == 1` in VictoriaMetrics.
- Stopping Traefik on websvcs for 5 minutes fires `HaproxyBackendConnectErrors` for the
  websvcs backends, once a request hits them.
- The dashboard shows non-zero drop rates from normal scanner traffic.

## Comments

- 2026-10-07: done. `frontend prometheus` on `127.0.0.1:8405` in `haproxy.cfg.j2`, the
  `haproxy` job in `src/nodes/vpnsvcs/prometheus.yml.j2`, `HaproxyDown` and
  `HaproxyBackendConnectErrors` in `vps.yml`, Grafana.com 12693 as `haproxy.json` with
  a "Dropped at the edge" row (frontend denied requests, `silent_drop_*` backends,
  backend connection errors) on top; it never used `haproxy_backend_up`. ADR 0007
  covers both tickets. Confirm the metric names and `haproxy -vv | grep -i prometheus`
  at apply (step 9).
- 2026-10-10: the exporter frontend moved from `127.0.0.1:8405` to the VPS's podman
  bridge gateway, `<vpnsvcs.container_subnet>.1:8405`, with observability/08's switch to
  container networking.
