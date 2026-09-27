# 04. Design: get HAProxy metrics from the VPS into VictoriaMetrics

Status: ready-for-agent
Type: research
Repo: homelab
Source: review finding 21

## Options

**A. HAProxy built-in exporter, scraped over the tailnet (recommended now).**
HAProxy ≥ 2.0 ships a Prometheus exporter; no extra process. In
`src/haproxy/haproxy.cfg.j2`:

```
frontend prometheus
    mode http
    bind {{ vpn.tailscale_ip }}:8405
    http-request use-service prometheus-exporter if { path /metrics }
    no log
```

Bind only on the Tailscale interface (so it is unreachable from the internet) and add
`tcp-request connection reject if !{ src 100.64.0.0/10 }` as belt-and-braces. Then
`src/secsvcs/prometheus.yml.j2` gets a `haproxy` job targeting
`{{ vpn.tailscale_ip }}:8405` — secsvcs's VictoriaMetrics is already a mesh peer (the
VMs are HAProxy's backends over Tailscale). Five lines of config, zero new software on
the VPS. Also scrape the VPS's node_exporter the same way (the VPS has none today —
install it via `src/vpn/install_svcs.sh`, bind to the tailnet IP).

**B. Podman + vmagent on the VPS, remote-writing to VictoriaMetrics.** More moving
parts, but collects node_exporter/fluentbit locally and is the foundation for
observability/08 (containerising the VPS services). Do this *after* A, when 08 lands.

**Not recommended:** exposing `:8405` publicly behind an ACL, or a separate
`haproxy_exporter` binary (deprecated in favour of the built-in one).

## Deliverable

- Implement A. Import Grafana.com dashboard **12693** ("HAProxy 2 Full") as
  `src/grafana/dashboards/haproxy.json`, fix datasource.
- Alerts: `HaproxyDown` (`up{job="haproxy"}==0`), `HaproxyBackendDown`
  (`haproxy_backend_up == 0`), and a panel for `haproxy_frontend_denied_connections_total`
  so you can finally see how much the edge is dropping.
- Record the decision as `docs/adr/0006-haproxy-metrics-over-tailnet.md`.

## Notes

`vpn.tailscale_ip` may need adding to `vars.yml`; Traefik's `trustedIPs` already
reference the VPS by `vpn.ip`.

## Comments

- 2026-09-27: ADR 0006 is now the node inventory (restructure/01); use the
  next free number.
