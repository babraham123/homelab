# 09. Explore long-term retention for an allowlist of series

Status: ready-for-agent
Type: research
Repo: homelab
Source: maintainer request 2026-09-26 (copyparty/03 retention decision)

## Problem

`retention.metric_days` is 14 and single-node VictoriaMetrics has one global retention.
Some series are worth keeping for years at low volume, such as car trips (copyparty/03),
finance_exporter tickers, disk usage trends and backup success timestamps. Raising the
global retention would keep all ~35 self-monitoring rule inputs and every node_exporter
series for years too.

## Options to evaluate

1. **Second VictoriaMetrics instance** (`victoriametrics-lt` on secsvcs, long
   `--retentionPeriod`), fed only with allowlisted series:
   - vmagent: a second `-remoteWrite.url` with per-URL
     `-remoteWrite.urlRelabelConfig` keeping only `__name__=~"car_.*|finance_.*|..."`;
   - direct imports: copyparty/03 writes car data straight to it.

   Grafana gets a second datasource.
2. **Downsampling.** `-downsampling.period` is VictoriaMetrics Enterprise only. Check
   whether that is still true, and whether stream aggregation (`-streamAggr.config` on
   vmagent, e.g. 1h averages) can produce low-resolution copies for the long-term
   instance instead.
3. **Raise global retention.** Size it: current `vm_data_size_bytes` × (N days / 14),
   against the free disk on secsvcs.

## Deliverable

- A recommendation with a disk estimate per option, and the allowlist (metric name
  regex) as a `vars.yml` key (`retention.long_term_allowlist`), so adding a series is
  one line.
- Interaction with backups: the long-term instance's data directory needs to be in the
  backup-and-dr/09 inventory, since it becomes data that can't be recreated.
- Whether car data should be re-imported from the copyparty CSV archive once this lands
  (backfill script).

## Comments
