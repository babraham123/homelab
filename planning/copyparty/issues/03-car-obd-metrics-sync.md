# 03. Sync OBD-II trip logs from copyparty into VictoriaMetrics

Status: ready-for-human
Type: task
Repo: homelab, car-ingest
Source: maintainer request 2026-09-26; `notes/TODO.md` "car data upload"
Blocked by: 01, 02

## Problem

Car Scanner Pro recordings (`.brc` files uploaded to copyparty `/car/`) have no path into the
metrics stack. Uploads are manual: the Termux auto-upload (04) is wontfix, and WiCAN Pro JSONL
batches are 05's.

## Change

- `car_ingest.py` (one stdlib Python script) in the car-ingest repo
  (<https://github.com/babraham123/car-ingest>), run on websvcs as the `car_ingest` container:
  `src/services/car_ingest/` holds its `build.sh`, quadlet and timer (every 15 min while websvcs is
  up), installed by a `car_ingest` case in `src/nodes/websvcs/install_svcs.sh`:
  - scan `/var/opt/copyparty/data/car/` (mounted at `/car`) for files not recorded in
    `/var/lib/car_ingest/state` (keyed by sha256, so re-uploads are skipped);
  - parse each `.brc` (format below) into `/api/v1/import/prometheus` lines with explicit
    timestamps: `car_<sensor>{unit="...",trip="<file stem>"}`, where `<sensor>` is the sensor name
    slugified (`[BMS] Battery Power` → `bms_battery_power`). Sample time = header start time +
    sample offset. The start time is phone-local, so convert it with `personal.timezone`
    (`CAR_INGEST_TIMEZONE`/`TZ` in the quadlet);
  - POST to `https://metrics.{{ site.url }}/api/v1/import/...` with the same basic-auth credentials
    vmagent uses (the `victoriametrics_admin_password` Podman secret);
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

The reference copy is the car-ingest repo's `docs/brc-format.md`. Decoded from the 02 sample
(`notes/2026-05-24 20-10-53.brc`); every sample matches the CSV export of the same recording. It
is .NET `BinaryWriter` output, little-endian; strings are 7-bit-varint length-prefixed UTF-8.

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

- 2026-10-12: Implemented: `src/nodes/websvcs/car_ingest.{sh.j2,service,timer}`,
  `car_ingest_brc.py` (the parser, stdlib Python), `install_svcs.sh car_ingest` + inventory,
  `src/services/grafana/dashboards/car.json`, `tests/car_ingest_test.sh`.
  - Checked against the 02 sample: 3587 samples, the same count and timestamps as its CSV export
    (first sample 20:12:09.4 local).
  - Unit enum 0 is `unit="none"`. Non-finite values are skipped. The .NET `DateTime` Kind bits
    are masked off the start ticks.
  - `too_old`: the oldest sample is before now − `retention.metric_days`; the hash is recorded so
    the file isn't retried every run. A failed POST stops the run unrecorded, so the file is
    retried.
  - `car_ingest_files_total` is counted from the state file (TSV: sha256, result, samples, time,
    name).
  - Dashboard: the trip selector reads `car_bms_battery_power`'s `trip` label; pack temperatures
    are `car_bms_battery_pack_b01`…`b16` plus min/max/inlet.
  Remaining for a human: install `car_ingest` on websvcs and grafana on secsvcs, upload the
  sample to `/car`, and check the dashboard.
- 2026-10-14: `car_ingest.sh.j2` and `car_ingest_brc.py` are one stdlib script,
  `src/nodes/websvcs/car_ingest.py.j2`; `car_ingest.py FILE` prints a file's import lines or
  why it fails. Still 3587 samples from the 02 sample. The tests now cover a whole run.
- 2026-10-25: car_ingest moved to its own repo, babraham123/car-ingest (`car_ingest.py`, its
  tests, `docs/brc-format.md`, `docs/wican-jsonl.md`), configured by `CAR_INGEST_*` environment
  variables. websvcs runs it as the `car_ingest` container from `src/services/car_ingest/`, built
  through the scan gate; the old host script, service and `tests/car_ingest_test.sh` are gone. The
  remaining deploy is repo-extraction/09.
