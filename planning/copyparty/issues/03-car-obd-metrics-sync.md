# 03. Sync OBD-II trip logs from copyparty into VictoriaMetrics

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-26; `notes/TODO.md` "car data upload"
Blocked by: 01, 02

## Problem

Car Scanner Pro trip logs (CSV exports uploaded from the phone) have no path into the
metrics stack.

## Change

- `src/websvcs/car_ingest.sh` + `car_ingest.{service,timer}` (every 15 min while
  websvcs is up), installed by a `car_ingest` case in `src/websvcs/install_svcs.sh`:
  - scan `/var/opt/copyparty/data/car/` for files not recorded in
    `/var/lib/car_ingest/state` (keyed by sha256, so re-uploads are skipped);
  - convert each file to VictoriaMetrics import format with the original sample
    timestamps: `car_<pid>{unit="...",trip="<file stem>"}` plus GPS lat/lon/speed if
    present. Car Scanner's CSV is reportedly long format, semicolon-separated
    (`"SECONDS";"PID";"VALUE";"UNITS"`). Confirm against the sample from 02, then
    pivot to `/api/v1/import/prometheus` lines with explicit timestamps. If `SECONDS`
    is relative, take the trip start from the filename or file header;
  - POST to `https://metrics.{{ site.url }}/api/v1/import/...` with the same basic-auth
    credentials vmagent uses (`VM_ADMIN_PASSWORD` from the websvcs secrets);
  - record file hash, sample count and outcome; move failed files to `car/failed/`;
  - write `car_ingest_last_success_timestamp_seconds` and
    `car_ingest_files_total{result=...}` to `/var/lib/node_exporter/textfile_collector/`.
- Grafana dashboard `src/grafana/dashboards/car.json`: trip selector (`trip` label),
  speed/RPM/coolant/fuel-trim/voltage panels, and a Geomap panel if GPS is present.
- Keep the raw CSVs in copyparty permanently. They are the source of truth and can be
  re-imported.

## Retention (decided)

`retention.metric_days` is 14 and VictoriaMetrics rejects samples older than that, so:
- car series are visible for two weeks;
- a trip uploaded more than 14 days late is not imported. Log it as
  `result="too_old"` and leave the file in place, not in `failed/`.

The CSVs in copyparty are the long-term archive. Long-term retention for an allowlist
of series (car data included) is explored in observability/09.

## Acceptance

- Uploading a sample trip produces series at the trip's original timestamps, visible on
  the dashboard.
- Re-uploading the same file adds no duplicate samples. A malformed file ends up in
  `car/failed/` and is counted in the metric.

## Comments
