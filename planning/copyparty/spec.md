# copyparty and car data upload

A file drop on websvcs (copyparty) behind Authelia, and a sync that turns Car Scanner
Pro trip logs uploaded from the phone into VictoriaMetrics series with a Grafana
dashboard.

Maintainer decisions (2026-09-26):
- The source is **Car Scanner Pro** CSV exports, uploaded from the phone.
- copyparty runs on **websvcs**.
- It may be reachable from the internet, **as long as every request is authenticated
  by Authelia**. Traefik must still see the real client IP.
- Raw CSVs are kept in copyparty as the long-term archive; VictoriaMetrics keeps its
  current 14-day retention for now. Long-term retention for an allowlist of series is
  explored in observability/09.

From `notes/TODO.md` "setup copyparty → car data upload".

Constraint: websvcs is on pve2, which is on demand, so uploads only work while pve2 is
up. Accepted.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-copyparty-on-websvcs.md) | Run copyparty on websvcs behind Authelia | `ready-for-agent` | task |
| [02](issues/02-car-scanner-sample-export.md) | Capture a sample Car Scanner Pro export | `ready-for-human` | task |
| [03](issues/03-car-obd-metrics-sync.md) | Sync Car Scanner Pro trip logs from copyparty into VictoriaMetrics | `ready-for-agent` | task |
| [04](issues/04-termux-auto-upload.md) | Auto-upload Car Scanner Pro exports from the phone with Termux | `ready-for-agent` | research |
