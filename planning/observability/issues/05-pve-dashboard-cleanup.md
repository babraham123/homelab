# 05. Remove or feed the empty pve.json dashboard

Status: resolved
Type: task
Repo: homelab
Source: review finding 22

## Correction to the finding

The maintainer is right about `proxmox.json`: it queries `cpustat_cpus`,
`memory_memtotal`, `system_used` etc., which come from PVE's built-in **Metric Server →
InfluxDB** push (`docs/guides/proxmox.md.j2:264`). VictoriaMetrics accepts InfluxDB line
protocol on its main HTTP port at `/write`, which is why it works even though
`--influxListenAddr` is commented out in `src/victoriametrics/victoriametrics.container.j2`.

`pve.json` was a different dashboard: it queried `pve_guest_info`, `pve_up`,
`pve_cpu_usage_limit`, `pve_memory_*` — the metric family of `prometheus-pve-exporter`,
which is not deployed or scraped anywhere. That dashboard was empty.

## Answer

Done in `9cdf062` ("grafana: upgrade dashboards, support metricsql"): `pve.json` is
deleted; `proxmox.json` (influx-fed) remains the PVE view.

Leftover, moved to ci-and-docs/04: a one-line comment in `victoriametrics.container.j2`
next to the commented `--influxListenAddr` explaining that PVE pushes over HTTP `/write`.

If a per-guest `pve_up == 0` alert is ever wanted, that is a new ticket
(`prometheus-pve-exporter` on secsvcs using the existing `api_ro` user).

## Comments

- 2026-09-26: closed during ticket review; the deletion had already shipped.
