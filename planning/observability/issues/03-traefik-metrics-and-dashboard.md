# 03. Expose Traefik Prometheus metrics, scrape them, add a dashboard

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 20

## Change

- `src/traefik/static.yml.j2`:
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
  `src/secsvcs/prometheus.yml.j2`, `src/homesvcs/prometheus.yml.j2`,
  `src/websvcs/prometheus.yml.j2` → `targets: ['{{ <node>.container_subnet }}.6:8082']`
  with `instance` relabelled to `<proxy>.SITE`. No `PublishPort` needed.
- Dashboard: import Grafana.com **17346** ("Traefik Official Standalone Dashboard",
  Traefik v2/v3, Prometheus) into `src/grafana/dashboards/traefik.json`; fix the
  datasource UID to the VictoriaMetrics one used by the other dashboards. Verify the
  ID before importing; 4475 is the older community one.
- Once router labels exist, add alerts: `Traefik5xxRate`
  (`sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) by (service) > 1`) and
  `TraefikCertExpiry` if `traefik_tls_certs_not_after` is present in your version.

## Acceptance

- `traefik_entrypoint_requests_total` visible in VictoriaMetrics for all three proxies;
  dashboard renders per-router request rate and latency.

## Comments
