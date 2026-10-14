# shellcheck shell=bash
# src/nodes/websvcs/car_ingest.py.j2 on .brc files written to the format decoded in
# planning/copyparty/issues/03: header start time is phone-local, sample time = start +
# offset, sensor names slugified, unit enums mapped (unknown ones to unknown_<n>), the
# trip label is the file stem, and any unexpected structure fails the file. Each file is
# imported once; malformed files move to failed/; trips past retention are too_old and
# never posted; a failed post records nothing, so the next run retries.
# shellcheck source=tests/lib.sh
source tests/lib.sh

# 2026-05-24 20:10:53 PDT, the recordings' start
start=1779678653
retention_days=14

# Renders the script with the fixture site's values; car_ingest.py's header has no Jinja
# besides these.
render_script() {
  cat > "${tmp}/vars.yml" <<EOF
site: {url: example.com}
personal: {timezone: America/Los_Angeles}
retention: {metric_days: ${retention_days}}
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
car_bms_battery_power{unit="kW",trip="trip1"} -12.25 $((start * 1000 + 1500))
car_odd_name_2{unit="unknown_99",trip="trip1"} 3.0 $((start * 1000 + 2000))
car_bms_battery_power{unit="kW",trip="trip1"} 4.5 $((start * 1000 + 120250))
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
car_bms_battery_power{unit="kW",trip="a"} -12.25 $((start * 1000 + 1500))
car_bms_battery_power{unit="kW",trip="a"} 4.5 $((start * 1000 + 120250))
EOF
  assert_eq "$(state)" <<'EOF'
ok	2	a.brc
EOF
  [[ -f ${tmp}/car/a.brc ]] || flunk "the recording left /car"
  assert_eq "$(cat "${tmp}/car_ingest.prom")" <<EOF
# HELP car_ingest_files_total Car Scanner recordings processed, by outcome.
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
