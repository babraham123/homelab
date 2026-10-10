# 03. Expose Traefik Prometheus metrics, scrape them, add a dashboard

Status: resolved Type: task Repo: homelab Source: review finding 20

## Change

- `src/services/traefik/static.yml.j2`:
  ```yaml
  entryPoints:
    metrics:
      address: ":8082/tcp"
  metrics:
    prometheus:
      entryPoint: metrics
      addEntryPointsLabels: true
      addRoutersLabels: true
      addServicesLabels: true
  ```
- Scrape from each node's collector, which is on the same `net.network` as Traefik:
  `src/nodes/secsvcs/prometheus.yml.j2`, `src/nodes/homesvcs/prometheus.yml.j2`,
  `src/nodes/websvcs/prometheus.yml.j2` → `targets: ['{{ <node>.container_subnet }}.6:8082']` with
  `instance` relabelled to `<proxy>.SITE`. No `PublishPort` needed.
- Dashboard: import Grafana.com **17346** ("Traefik Official Standalone Dashboard", Traefik v2/v3,
  Prometheus) into `src/services/grafana/dashboards/traefik.json`; fix the datasource UID to the
  VictoriaMetrics one used by the other dashboards. Verify the ID before importing; 4475 is the
  older community one.
- Once router labels exist, add alerts: `Traefik5xxRate`
  (`sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) by (service) > 1`) and
  `TraefikCertExpiry` if `traefik_tls_certs_not_after` is present in your version.

## Acceptance

- `traefik_entrypoint_requests_total` visible in VictoriaMetrics for all three proxies; dashboard
  renders per-router request rate and latency.

## Comments

- 2026-10-07: done. `metrics` entrypoint `:8082`, `traefik` job in the three `prometheus.yml.j2`
  (`instance` = secproxy/homeproxy/webproxy, `host` = node), Grafana.com 17346 rev 9 as
  `traefik.json` with the datasource swapped to VictoriaMetrics, a `host` variable scoping every
  query, and two access-log panels. `Traefik5xxRate` and `TraefikCertExpiry` are in `homelab.yml`.
