# shellcheck shell=bash
# src/nodes/websvcs/car_ingest.py.j2 on .brc files written to the format decoded in
# planning/copyparty/issues/03: header start time is phone-local, sample time = start +
# offset, sensor names slugified, unit enums mapped (unknown ones to unknown_<n>), the
# trip label is the file stem, the car label cars.default, and any unexpected structure
# fails the file. On WiCAN batches (planning/copyparty/issues/05), plain or gzipped:
# marker and meta lines skipped, journal/device/anchor rows imported at ts, unknown rows
# dropped, the dashboard's params mapped onto the Car Scanner series, trips split by gaps
# of more than 10 min and continued across a car's batches, and the car label from the
# dongle id in the file name through cars.sources. Each file is imported once; malformed
# files move to failed/; files past retention are too_old and never posted; a failed post
# records nothing, so the next run retries.
# shellcheck source=tests/lib.sh
source tests/lib.sh

# 2026-05-24 20:10:53 PDT, the recordings' start
start=1779678653
retention_days=14
# Dongle ids as the sync app writes them into batch names; only the first is in cars.sources
ev6=wican_AA_BB_CC_DD_EE_01
other=wican_AA_BB_CC_DD_EE_02

# Renders the script with the fixture site's values; car_ingest.py's header has no Jinja
# besides these.
render_script() {
  cat > "${tmp}/vars.yml" <<EOF
site: {url: example.com}
personal: {timezone: America/Los_Angeles}
retention: {metric_days: ${retention_days}}
cars: {default: ev6, sources: {${ev6}: ev6}}
EOF
  jinjanate --quiet src/nodes/websvcs/car_ingest.py.j2 "${tmp}/vars.yml" > "${tmp}/car_ingest.py"
}

# Usage: brc FILE [RECORD...]; writes a recording started 2026-05-24 20:10:53 local time.
# RECORD is def:ID:NAME:UNIT, sample:OFFSET:ID:VALUE or marker:HEX.
brc() {
  python3 -I - "$@" <<'EOF'
import datetime, struct, sys

def string(s):
    b = s.encode()
    n, out = len(b), bytearray()
    while True:
        out.append((n & 0x7F) | (0x80 if n > 0x7F else 0))
        n >>= 7
        if not n:
            return bytes(out) + b

ticks = (datetime.datetime(2026, 5, 24, 20, 10, 53) - datetime.datetime(1, 1, 1)) \
    // datetime.timedelta(microseconds=1) * 10
out = string("CARSCANNERRECORD") + struct.pack("<i", 2)
out += b"".join(string(s) for s in ("VIN0000", "My car", "Kia e-GMP", "BT vLinker MC"))
out += struct.pack("<q", ticks)
for record in sys.argv[2:]:
    kind, *f = record.split(":")
    if kind == "def":
        out += struct.pack("<Ii", 0x00D56190, int(f[0])) + string(f[1]) + string("short") \
            + struct.pack("<i", int(f[2]))
    elif kind == "sample":
        out += struct.pack("<Idid", 0x01274350, float(f[0]), int(f[1]), float(f[2]))
    else:
        out += struct.pack("<I", int(f[0], 16))
open(sys.argv[1], "wb").write(out)
EOF
}

convert() {
  render_script
  python3 -I "${tmp}/car_ingest.py" "$1"
}

# Usage: ingest NOW; runs ingest() over $tmp/car with $tmp/state and $tmp/car_ingest.prom.
# The post appends each body to $tmp/posted, or fails while $tmp/post_fails exists.
ingest() {
  render_script
  python3 -I - "$tmp" "$1" <<'EOF'
import importlib.util, pathlib, sys
tmp = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("car_ingest", tmp / "car_ingest.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def post(body):
    if (tmp / "post_fails").exists():
        raise OSError("connection refused")
    with open(tmp / "posted", "ab") as f:
        f.write(body)

m.ingest(tmp / "car", tmp / "state", tmp / "car_ingest.prom", post, float(sys.argv[2]))
EOF
}

# Usage: upload NAME [RECORD...]; a recording in $tmp/car, last modified at the start
upload() {
  mkdir -p "${tmp}/car"
  brc "${tmp}/car/$1" "${@:2}"
  touch -t 202605242300 "${tmp}/car/$1"
}

# Usage: batch NAME [gz]; stdin as a WiCAN batch in $tmp/car, gzipped with gz, last
# modified at the start
batch() {
  mkdir -p "${tmp}/car"
  if [[ ${2:-} == gz ]]; then gzip -c > "${tmp}/car/$1"; else cat > "${tmp}/car/$1"; fi
  touch -t 202605242300 "${tmp}/car/$1"
}

# Usage: row SECONDS PARAM VALUE [QUALITY]; a logger row SECONDS after the start
row() {
  local ms=$(((start + $1) * 1000))
  [[ ${4:-} == unknown ]] && ms=null
  printf '{"ts":%s,"param":"autopid.%s","value":%s,"ts_quality":"%s","ts_raw":%s}\n' \
    "$ms" "$2" "$3" "${4:-device}" "$(((start + $1) * 1000))"
}

# Usage: name DONGLE CURSOR [OFFSET]; a batch file name as the sync app writes it
name() {
  echo "${1}-${2}_${3:-0}-0123456789abcdef.jsonl.gz"
}

# Columns 2, 3 and 5 of the state file: result, samples, file name
state() {
  cut -f 2,3,5 "${tmp}/state"
}

trip=('def:7:[BMS] Battery Power:46' 'sample:1.5:7:-12.25' 'sample:120.25:7:4.5')
# A day after the start: inside retention, and the upload long settled
day_later=$((start + 86400))

test_converts_samples_at_local_start_plus_offset() {
  brc "${tmp}/trip1.brc" 'def:7:[BMS] Battery Power:46' 'sample:1.5:7:-12.25' \
    'def:9:Odd "Name" 2:99' 'sample:2:9:3' 'sample:3:9:nan' 'sample:120.25:7:4.5'
  assert_eq "$(convert "${tmp}/trip1.brc")" <<EOF
car_bms_battery_power{unit="kW",trip="trip1",car="ev6"} -12.25 $((start * 1000 + 1500))
car_odd_name_2{unit="unknown_99",trip="trip1",car="ev6"} 3.0 $((start * 1000 + 2000))
car_bms_battery_power{unit="kW",trip="trip1",car="ev6"} 4.5 $((start * 1000 + 120250))
EOF
}

test_fails_unknown_marker() {
  brc "${tmp}/t.brc" 'def:7:Power:46' 'sample:1:7:1' 'marker:deadbeef'
  convert "${tmp}/t.brc" > /dev/null 2>&1 && flunk "accepted an unknown marker"
  true
}

test_fails_sample_before_its_definition() {
  brc "${tmp}/t.brc" 'sample:1:7:1' 'def:7:Power:46'
  convert "${tmp}/t.brc" > /dev/null 2>&1 && flunk "accepted an undefined sensor"
  true
}

test_fails_truncated_file() {
  brc "${tmp}/t.brc" 'def:7:Power:46' 'sample:1:7:1'
  # Portable head -c -3
  head -c "$(( $(wc -c < "${tmp}/t.brc") - 3 ))" "${tmp}/t.brc" > "${tmp}/cut.brc"
  convert "${tmp}/cut.brc" > /dev/null 2>&1 && flunk "accepted a truncated file"
  true
}

test_fails_without_samples() {
  brc "${tmp}/t.brc" 'def:7:Power:46'
  convert "${tmp}/t.brc" > /dev/null 2>&1 && flunk "accepted a file without samples"
  true
}

test_fails_other_files() {
  printf '"SECONDS";"PID";"VALUE";"UNITS";\n' > "${tmp}/t.csv"
  convert "${tmp}/t.csv" > /dev/null 2>&1 && flunk "accepted a CSV"
  true
}

test_imports_each_recording_once() {
  upload a.brc "${trip[@]}"
  ingest "$day_later" > /dev/null
  # The same recording uploaded again under another name
  cp -p "${tmp}/car/a.brc" "${tmp}/car/b.brc"
  ingest "$((day_later + 900))" > /dev/null
  assert_eq "$(cat "${tmp}/posted")" <<EOF
car_bms_battery_power{unit="kW",trip="a",car="ev6"} -12.25 $((start * 1000 + 1500))
car_bms_battery_power{unit="kW",trip="a",car="ev6"} 4.5 $((start * 1000 + 120250))
EOF
  assert_eq "$(state)" <<'EOF'
ok	2	a.brc
EOF
  [[ -f ${tmp}/car/a.brc ]] || flunk "the recording left /car"
  assert_eq "$(cat "${tmp}/car_ingest.prom")" <<EOF
# HELP car_ingest_files_total Car recordings and logger batches processed, by outcome.
# TYPE car_ingest_files_total counter
car_ingest_files_total{result="ok"} 1
car_ingest_files_total{result="failed"} 0
car_ingest_files_total{result="too_old"} 0
# HELP car_ingest_last_success_timestamp_seconds Unix time of the last car_ingest run that completed.
# TYPE car_ingest_last_success_timestamp_seconds gauge
car_ingest_last_success_timestamp_seconds $((day_later + 900))
EOF
}

test_moves_malformed_recordings_to_failed() {
  upload bad.brc 'sample:1:7:1'
  ingest "$day_later" > /dev/null 2>&1
  [[ -f ${tmp}/car/failed/bad.brc && ! -e ${tmp}/car/bad.brc ]] || flunk "bad.brc not in failed/"
  [[ ! -e ${tmp}/posted ]] || flunk "posted a malformed recording"
  assert_eq "$(state)" <<'EOF'
failed	0	bad.brc
EOF
  grep -qx 'car_ingest_files_total{result="failed"} 1' "${tmp}/car_ingest.prom" \
    || flunk "failed not counted"
}

test_records_trips_past_retention_as_too_old() {
  upload old.brc "${trip[@]}"
  ingest "$((start + (retention_days + 1) * 86400))" > /dev/null
  [[ ! -e ${tmp}/posted ]] || flunk "posted samples VictoriaMetrics would drop"
  [[ -f ${tmp}/car/old.brc ]] || flunk "the recording left /car"
  assert_eq "$(state)" <<'EOF'
too_old	2	old.brc
EOF
}

test_retries_a_failed_post_on_the_next_run() {
  upload a.brc "${trip[@]}"
  touch "${tmp}/post_fails"
  ingest "$day_later" > /dev/null 2>&1 && flunk "a failed post didn't stop the run"
  [[ ! -s ${tmp}/state ]] || flunk "recorded a file that wasn't imported"
  [[ ! -e ${tmp}/car_ingest.prom ]] || flunk "a failed run counted as a success"
  rm "${tmp}/post_fails"
  ingest "$((day_later + 900))" > /dev/null
  assert_eq "$(state)" <<'EOF'
ok	2	a.brc
EOF
}

test_skips_recordings_still_uploading() {
  upload a.brc "${trip[@]}"
  # Modified 30 s before the run
  ingest "$(( $(stat -c %Y "${tmp}/car/a.brc" 2> /dev/null || stat -f %m "${tmp}/car/a.brc") + 30 ))" \
    > /dev/null
  [[ ! -s ${tmp}/state && ! -e ${tmp}/posted ]] || flunk "imported a recording still uploading"
}

test_imports_plain_and_gzipped_batches() {
  { echo '{"_file":"dl_1779678653.jsonl"}'; row 0 SOC 80; } | batch "$(name "$ev6" 1)" gz
  { row 60 SOC 79.5; echo '{"_cursor":"1779678713:2","more":false}'; } \
    | batch "${ev6}-2_0-fedcba9876543210.jsonl"
  ingest "$day_later" > /dev/null
  assert_eq "$(cat "${tmp}/posted")" <<EOF
car_bms_state_of_charge_bms{unit="%",trip="2026-05-24 20-10-53",car="ev6"} 80.0 $((start * 1000))
car_bms_state_of_charge_bms{unit="%",trip="2026-05-24 20-10-53",car="ev6"} 79.5 $(((start + 60) * 1000))
EOF
}

test_imports_rows_by_ts_quality() {
  { row 0 SOC 80 journal; row 1 SOC 81; row 2 SOC 82 anchor; row 3 SOC 83 unknown; } \
    | batch "$(name "$ev6" 1)" gz
  ingest "$day_later" > "${tmp}/log"
  grep -q 'dropped 1 rows with an unknown time' "${tmp}/log" || flunk "the dropped row wasn't logged"
  assert_eq "$(cut -d' ' -f 3,4 "${tmp}/posted")" <<EOF
80.0 $((start * 1000))
81.0 $(((start + 1) * 1000))
82.0 $(((start + 2) * 1000))
EOF
}

test_fails_malformed_batches() {
  local bad
  for bad in 'not json' '{"param":"autopid.SOC"}' "$(row 0 SOC 80 guessed)" \
    '{"ts":null,"param":"autopid.SOC","value":80,"ts_quality":"device"}' "$(row 0 SOC true)"; do
    { row 0 SOC 80; echo "$bad"; } > "${tmp}/t.jsonl"
    convert "${tmp}/t.jsonl" > /dev/null 2>&1 && flunk "accepted: $bad"
  done
  row 0 SOC 80 unknown > "${tmp}/t.jsonl"
  convert "${tmp}/t.jsonl" > /dev/null 2>&1 && flunk "accepted a batch without importable rows"
  { row 0 SOC 80; echo 'not json'; } | batch "$(name "$ev6" 1)" gz
  ingest "$day_later" > /dev/null 2>&1
  [[ -f ${tmp}/car/failed/$(name "$ev6" 1) && ! -e ${tmp}/posted ]] || flunk "not moved to failed/"
}

test_maps_params_onto_car_scanner_series() {
  { row 0 HV_W -12250; row 0 HV_T_3 21; row 0 TYRE_P_FL 38; row 0 IGNITION 1; row 0 NEW_THING 2; } \
    > "${tmp}/t.jsonl"
  assert_eq "$(convert "${tmp}/t.jsonl")" <<EOF
car_bms_battery_power{unit="kW",trip="2026-05-24 20-10-53",car="ev6"} -12.25 $((start * 1000))
car_bms_battery_pack_b03{unit="°C",trip="2026-05-24 20-10-53",car="ev6"} 21.0 $((start * 1000))
car_tyre_p_fl{unit="psi",trip="2026-05-24 20-10-53",car="ev6"} 38.0 $((start * 1000))
car_ignition{unit="unknown",trip="2026-05-24 20-10-53",car="ev6"} 1.0 $((start * 1000))
car_new_thing{unit="unknown",trip="2026-05-24 20-10-53",car="ev6"} 2.0 $((start * 1000))
EOF
}

test_splits_trips_on_gaps_and_continues_them_across_batches() {
  # 10 min apart continues; 10 min and 1 s apart starts a new trip
  { row 0 SOC 80; row 600 SOC 79; row 1201 SOC 78; } | batch "$(name "$ev6" 1)" gz
  row 1500 SOC 77 | batch "$(name "$ev6" 2)" gz
  ingest "$day_later" > /dev/null
  assert_eq "$(sed -E 's/.*trip="([^"]*)".* ([0-9.]+) [0-9]+$/\1 \2/' "${tmp}/posted")" <<'EOF'
2026-05-24 20-10-53 80.0
2026-05-24 20-10-53 79.0
2026-05-24 20-30-54 78.0
2026-05-24 20-30-54 77.0
EOF
}

test_labels_each_dongle_as_its_own_car() {
  upload trip.brc "${trip[@]}"
  # Interleaved in time: neither dongle's batches continue the other's trip
  row 0 SOC 80 | batch "$(name "$ev6" 1)" gz
  row 120 SOC 50 | batch "$(name "$other" 1)" gz
  row 240 SOC 79 | batch "$(name "$ev6" 2)" gz
  row 600 SOC 49 | batch "$(name "$other" 2)" gz
  ingest "$day_later" > /dev/null 2> "${tmp}/err"
  grep -q "dongle ${other} isn't in cars.sources" "${tmp}/err" || flunk "the unmapped dongle wasn't logged"
  assert_eq "$(sed -E 's/^([a-z_0-9]+)\{[^}]*trip="([^"]*)",car="([^"]*)"\} ([0-9.-]+) [0-9]+$/\1 \3 \2 \4/' "${tmp}/posted")" <<EOF
car_bms_battery_power ev6 trip -12.25
car_bms_battery_power ev6 trip 4.5
car_bms_state_of_charge_bms ev6 2026-05-24 20-10-53 80.0
car_bms_state_of_charge_bms ev6 2026-05-24 20-10-53 79.0
car_bms_state_of_charge_bms ${other} 2026-05-24 20-12-53 50.0
car_bms_state_of_charge_bms ${other} 2026-05-24 20-12-53 49.0
EOF
}

test_imports_a_batch_once() {
  row 0 SOC 80 | batch "$(name "$ev6" 1)" gz
  ingest "$day_later" > /dev/null
  cp -p "${tmp}/car/$(name "$ev6" 1)" "${tmp}/car/$(name "$ev6" 9)"
  ingest "$((day_later + 900))" > /dev/null
  assert_eq "$(wc -l < "${tmp}/posted" | tr -d ' ')" <<<1
  assert_eq "$(state)" <<EOF
ok	1	$(name "$ev6" 1)
EOF
}

test_orders_batches_by_cursor_offset_as_a_number() {
  # By name, offset 10000 sorts before 9000 and would start a second trip at 16 min
  row 0 SOC 80 | batch "$(name "$ev6" 1 0)" gz
  row 480 SOC 79 | batch "$(name "$ev6" 1 9000)" gz
  row 960 SOC 78 | batch "$(name "$ev6" 1 10000)" gz
  ingest "$day_later" > /dev/null
  assert_eq "$(sed -E 's/.*trip="([^"]*)".* ([0-9.]+) [0-9]+$/\1 \2/' "${tmp}/posted")" <<'EOF'
2026-05-24 20-10-53 80.0
2026-05-24 20-10-53 79.0
2026-05-24 20-10-53 78.0
EOF
}
