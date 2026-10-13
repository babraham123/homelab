# 03. Sync OBD-II trip logs from copyparty into VictoriaMetrics

Status: ready-for-agent Type: task Repo: homelab Source: maintainer request 2026-09-26;
`notes/TODO.md` "car data upload" Blocked by: 01, 02

## Problem

Car Scanner Pro recordings (`.brc` files uploaded from the phone by 04) have no path into the
metrics stack.

## Change

- `src/nodes/websvcs/car_ingest.sh` + `car_ingest.{service,timer}` (every 15 min while websvcs is
  up), installed by a `car_ingest` case in `src/nodes/websvcs/install_svcs.sh`:
  - scan `/var/opt/copyparty/data/car/` for files not recorded in `/var/lib/car_ingest/state` (keyed
    by sha256, so re-uploads are skipped);
  - parse each `.brc` (format below) into `/api/v1/import/prometheus` lines with explicit
    timestamps: `car_<sensor>{unit="...",trip="<file stem>"}`, where `<sensor>` is the sensor name
    slugified (`[BMS] Battery Power` → `bms_battery_power`). Sample time = header start time +
    sample offset. The start time is phone-local, so convert it with `personal.timezone`;
  - POST to `https://metrics.{{ site.url }}/api/v1/import/...` with the same basic-auth credentials
    vmagent uses (`VM_ADMIN_PASSWORD` from the websvcs secrets);
  - record file hash, sample count and outcome; move failed files to `car/failed/`;
  - write `car_ingest_last_success_timestamp_seconds` and `car_ingest_files_total{result=...}` to
    `/var/lib/node_exporter/textfile_collector/`.
- Grafana dashboard `src/services/grafana/dashboards/car.json`: trip selector (`trip` label) and EV
  panels: SoC, battery power/current/voltage, min/max cell voltage and deviation, pack
  temperatures, cumulative energy charged/discharged, 12 V voltage. The car is a Kia EV6, so there
  is no RPM/coolant/fuel trim, and the sample has no GPS.
- Keep the raw `.brc` files in copyparty permanently. They are the source of truth and can be
  re-imported.

## BRC format

Decoded from the 02 sample (`notes/2026-05-24 20-10-53.brc`); every sample matches the CSV export
of the same recording. It is .NET `BinaryWriter` output, little-endian; strings are 7-bit-varint
length-prefixed UTF-8.

| Part | Layout |
| --- | --- |
| Header | string `"CARSCANNERRECORD"`, int32 version (`2`), strings VIN, car name, car profile, adapter (`BT vLinker MC-Android [MAC]`), int64 .NET `DateTime` ticks of recording start (Kind=Unspecified, i.e. phone-local time) |
| Sensor def | uint32 `0x00D56190`, int32 sensor id, string name, string short name, int32 unit enum |
| Sample | uint32 `0x01274350`, float64 seconds since start, int32 sensor id, float64 value |

- Defs and samples interleave. A def precedes its sensor's first sample. Fail the file on any other
  marker.
- Values are SI regardless of the app's display units (°C, not the CSV's °F).
- Unit enums seen: 0 none, 3 distance (probably km; the sample only has zeros), 6 rpm, 10 V, 14 %,
  15 °C, 17 s, 18 min, 27 kOhm, 30 Hz, 46 kW, 54 h, 58 currency, 59 A, 60 kWh, 61 Wh, 62 Ah,
  63 hours. Map an unknown enum to `unit="unknown_<n>"` rather than failing.
- Use the header's VIN as a `vin` label only if a second car appears. Don't publish it otherwise.

## Retention (decided)

`retention.metric_days` is 14 and VictoriaMetrics rejects samples older than that, so:

- car series are visible for two weeks;
- a trip uploaded more than 14 days late is not imported. Log it as `result="too_old"` and leave the
  file in place, not in `failed/`.

The `.brc` files in copyparty are the long-term archive. Long-term retention for an allowlist of
series (car data included) is explored in observability/09.

## Acceptance

- Uploading a sample trip produces series at the trip's original timestamps, visible on the
  dashboard.
- Re-uploading the same file adds no duplicate samples. A malformed file ends up in `car/failed/`
  and is counted in the metric.

## Comments
