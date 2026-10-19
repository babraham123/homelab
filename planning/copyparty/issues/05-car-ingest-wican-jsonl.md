# 05. Ingest WiCAN Pro logger batches (JSONL) in car_ingest

Status: ready-for-human
Type: task
Repo: homelab
Source: wican1 session 2026-10-14 (WiCAN Pro BLE-sync app, a separate GPL-3.0 Android repo)
Blocked by: 03

## Problem

Car data moves from Car Scanner `.brc` recordings to a WiCAN Pro OBD dongle. The dongle polls the
car itself and logs to its SD card. A phone app pulls the log over BLE and uploads it to copyparty
`/car/` as `car_uploader`. `car_ingest` only parses `.brc`.

## Upload format (decided by the app)

- One file per batch, gzipped, named `<name>.jsonl.gz`, sent as an HTTP `PUT` to
  `https://files.{{ site.url }}/car/`. Auth is Basic as `car_uploader` for now, bearer later (06).
  `Content-Encoding` is not relied on.
- A batch is a sealed slice of
  `GET /api/logger/export?format=jsonl&stream=params&since=<cursor>&limit=N`, cut at the logger's
  `_file` boundaries. The app guarantees batches are disjoint: each row is in exactly one batch,
  and a re-sent batch is byte-identical, so the sha256 dedup catches it. That's why
  VictoriaMetrics needs no `-dedup.minScrapeInterval`.
- Lines (row shape per meatpi-components `components/data_logger/README.md`):
  - first, `{"_file":"dl_<epoch>.jsonl"}`;
  - rows: `{"ts":<epoch ms>,"param":"<source>.<name>","value":<number>,"ts_quality":"…",
    "ts_raw":<epoch ms>}`, e.g. `"param":"autopid.SOC"`. `ts_raw` is the device's original
    stamp; `ts` is the app's corrected time, and `ts_quality` says how it got it:

    | `ts_quality` | `ts` | Import |
    | --- | --- | --- |
    | `journal` | a clock-journal step (`/sd/logs/clock.jsonl`) applied to `ts_raw` | yes |
    | `device` | `ts_raw` as-is: plausible, kept (most rows) | yes |
    | `anchor` | an implausible `ts_raw` corrected by the phone/device clock offset | yes |
    | `unknown` | `null` | no |

  - possibly a trailing `{"_cursor":"<epoch>:<offset>","more":<bool>}` meta line.
- Param names are WiCAN's, unchanged. The app is device-agnostic and never renames them.

## Change

- `car_ingest.py` accepts `.jsonl.gz` and `.jsonl` next to `.brc`; gzip is recognised by its magic
  bytes.
- Skip `_file` and `_cursor` lines. Fail the file on any other line that isn't a row. Ignore
  `ts_raw`.
- `ts_quality`: import `journal`, `device` and `anchor` rows. Drop `unknown` ones (`ts` is `null`)
  and log how many were dropped. A label would split every series. Any other value, or a `null`
  `ts` with another quality, fails the file, as does a file with no importable rows.
- **Series names:** map the WiCAN params the Car dashboard charts onto its existing Car Scanner
  series, so `car.json` serves both sources unchanged. Units come from wican-fw
  `vehicle_profiles.json` (`Kia: EV6`):

  | WiCAN param (unit) | Series (unit label) |
  | --- | --- |
  | `SOC` (%) | `car_bms_state_of_charge_bms` (%) |
  | `SOC_D` (%) | `car_bms_state_of_charge_display` (%) |
  | `HV_W` (W, ÷ 1000) | `car_bms_battery_power` (kW) |
  | `HV_A` (A) | `car_bms_battery_current` (A) |
  | `HV_V` (V) | `car_bms_battery_dc_voltage` (V) |
  | `HV_C_V_MAX` / `HV_C_V_MIN` (V) | `car_bms_maximum_cell_voltage` / `car_bms_minimum_cell_voltage` (V) |
  | `HV_C_DIFF` (V) | `car_bms_battery_cell_voltage_deviation` (V) |
  | `HV_T_MAX` / `HV_T_MIN` (°C) | `car_bms_battery_max_temperature` / `car_bms_battery_min_temperature` (°C) |
  | `HV_T_1`…`HV_T_16` (°C) | `car_bms_battery_pack_b01`…`b16` (°C) |
  | `KWH_CHARGED` / `KWH_DISCHARGED` (kWh) | `car_bms_cumulative_energy_charged` / `…_discharged` (kWh) |
  | `LV_V` (V) | `car_bms_auxillary_battery_voltage` (V) |

  Any other param is `car_<slug(name)>` with its profile unit, or `unknown` if the profile has
  none. `car_bms_battery_inlet_temperature` and `car_obd_module_voltage` have no WiCAN source and
  stay `.brc`-only.
- **`trip` label:** a trip starts at the first row after a gap of more than 10 min. That covers a
  trip spread over several batches and a batch holding several trips. The label is the trip's
  first row in local time (`personal.timezone`) formatted `%Y-%m-%d %H-%M-%S`. That is the shape
  of Car Scanner's file stems, so `.brc` files keep their stem and the dashboard's trip selector
  lists both sources the same way. Record the last imported row's time and trip per car in the
  state directory, so the next batch from that car continues its trip if it starts within 10 min.
- **`car` label** on every series, so two cars never share a series or a trip:
  - The app names each batch `<source>-<cursor>-<sha256 prefix>.jsonl.gz`, with `<source>` the
    dongle's id (`wican:<BLE MAC>`) and every character outside `[A-Za-z0-9._-]` replaced by `_`,
    e.g. `wican_AA_BB_CC_DD_EE_01-1784000060_0-0123456789abcdef.jsonl.gz`. Take `<source>` as the
    name's stem with its last two `-` fields removed (the cursor and hash contain no `-`).
  - A new `cars` map in `vars.yml` (and `vars.template.yml`) names each source:
    `cars: {default: ev6, sources: {wican_AA_BB_CC_DD_EE_01: ev6}}`. The label is the mapped name;
    an unmapped source is labelled with the source itself and logged, so a new dongle shows up as
    its own car rather than merging into one. `.brc` files and JSONL names without the
    `<source>-<cursor>-<hash>` shape get `cars.default`.
  - The id is the dongle's, not the car's: moving a dongle to another car means editing the map.
  - Car dashboard (`src/services/grafana/dashboards/car.json`): a `car` variable
    (`label_values(car)`), the trip selector filtered by it, and `car="$car"` on every panel query.
  - 03 isn't deployed yet, so no imported series lack the label and nothing needs backfilling.
- Unchanged from 03: sha256 dedup, malformed files to `failed/`, `too_old` judged on the oldest
  row, a failed POST records nothing, the textfile metrics.
- Tests in `tests/car_ingest_test.sh`, sharing the existing `ingest()` and `state()` helpers:
  - plain and gzipped batches;
  - marker and meta lines skipped, a malformed line fails the file;
  - `journal`, `device` and `anchor` rows imported at `ts`, `unknown` rows dropped, an unlisted
    `ts_quality` fails the file;
  - param mapping and the W → kW conversion;
  - a trip split by a gap of more than 10 min, and one continued across two batches;
  - two sources' interleaved batches: separate `car` labels and trips, and a batch from one car
    never continues the other's trip; an unmapped source labelled by its id; `.brc` gets
    `cars.default`;
  - a re-uploaded batch imports nothing.

## To verify on the first real batches

The app side plans a first drive with Car Scanner logging through the Pro's ELM327-over-BLE
emulation alongside AutoPID (`obd_gate` shares the bus), then a row-by-row comparison. Results go in
this ticket's comments.

- **Sign:** `HV_A = ((S17*256)+B18)/10` is signed and `HV_W = HV_V × HV_A`, so both follow the
  BMS's sign convention for current. Compare them with Car Scanner's battery power (−12.25 kW in
  the sample) and negate in the mapping if the two disagree.
- **Cumulative counters:** wican-fw's EV6 profile misreads `KWH_DISCHARGED` and `HV_AH_CHARGED`.
  That fix has its own ticket from the app side and is made on the dongle, so ingest needs no
  special case.

## Acceptance

- A batch uploaded by the app produces series at the rows' original timestamps, on the existing
  Car dashboard panels, under a trip label like a `.brc` trip's and the `car` label its source
  maps to.
- Re-uploading a batch adds no samples; a malformed batch ends up in `car/failed/`; `unknown` rows
  are never imported.

## Comments

- 2026-10-14: The app side (wican1) answered the open questions: the app never renames params
  (map them here), it has no notion of trips (gap of more than 10 min, derived here), batches are
  disjoint and re-sends are byte-identical (no VictoriaMetrics dedup flag), rows carry `ts_raw`
  next to `ts_quality`, and the `.jsonl.gz` extension is always present.
- 2026-10-14: `ts_quality` has four values: `device` (the raw stamp kept, most rows) joins
  `journal`, `anchor` and `unknown`; `unknown` rows have `"ts":null`.
- 2026-10-17: 03's code is in (`src/nodes/websvcs/car_ingest.py.j2`, `tests/car_ingest_test.sh`);
  only its deploy and live check remain, so this ticket's code can build on it now.
- 2026-10-18: Added the `car` label: the source id comes from the app's batch file name (rows
  carry none), mapped to a name through `cars` in `vars.yml`; trips are tracked per car; the Car
  dashboard gets a car selector.
- 2026-10-18 agent: done in `src/nodes/websvcs/car_ingest.py.j2` and `tests/car_ingest_test.sh`
  (the seven cases above), `cars` in `vars.template.yml`, and the Car dashboard's `car` variable.
  Trip state is `/var/lib/car_ingest/trips` (car, last row ms, trip), written only after a
  successful post. A batch name matches `<source>-<digits>_<digits>-<hex>`; anything else gets
  `cars.default`. Units for unmapped params come from the EV6 profile in the sync app's copy of
  `vehicle_profiles.json`. Left for the maintainer: put the dongle's id under `cars.sources` in
  `vars.yml`, deploy with 03, and check the first real batches (sign, counters).
