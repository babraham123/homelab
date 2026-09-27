# Observability gaps

The pipeline exists but monitors mostly itself: no useful alerts, no HTTP access logs,
no Traefik or HAProxy metrics, an empty PVE dashboard, and 10-minute uptime intervals.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-node-and-service-alerts.md) | Add vmalert rules for hosts, disks, systemd units, backups and auth | `ready-for-agent` | task |
| [02](issues/02-traefik-access-logs.md) | Enable Traefik access logs and ship them to VictoriaLogs | `ready-for-agent` | task |
| [03](issues/03-traefik-metrics-and-dashboard.md) | Expose Traefik Prometheus metrics, scrape them, add a dashboard | `ready-for-agent` | task |
| [04](issues/04-haproxy-metrics-design.md) | Design: get HAProxy metrics from the VPS into VictoriaMetrics | `resolved` (loopback exporter + VPS vmagent push, folded into 08) | research |
| [05](issues/05-pve-dashboard-cleanup.md) | Remove or feed the empty pve.json dashboard | `resolved` (shipped in `9cdf062`) | task |
| [06](issues/06-cert-expiry-alerts.md) | Add the cert-expiry vmalert rules the docs already claim exist | `ready-for-agent` | task |
| [07](issues/07-gatus-tier1-interval.md) | Check tier-1 services every 2 minutes in Gatus | `ready-for-agent` | task |
| [08](issues/08-vpn-node-containers.md) | Install Podman on the VPS and containerise node_exporter, fluent-bit and vmagent | `ready-for-agent` | task |
| [09](issues/09-long-term-retention-allowlist.md) | Explore long-term retention for an allowlist of series | `ready-for-agent` | research |
| [10](issues/10-alerting-pipeline-e2e.md) | Validate the alerting pipeline end to end | `ready-for-agent` | task |
