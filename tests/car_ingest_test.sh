# shellcheck shell=bash
# src/nodes/websvcs/car_ingest_brc.py on .brc files written to the format decoded in
# planning/copyparty/issues/03: header start time is phone-local, sample time = start +
# offset, sensor names slugified, unit enums mapped (unknown ones to unknown_<n>), and
# any unexpected structure fails the file.
# shellcheck source=tests/lib.sh
source tests/lib.sh

parser=src/nodes/websvcs/car_ingest_brc.py

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
  python3 -I "$parser" "$1" trip1 America/Los_Angeles
}

test_converts_samples_at_local_start_plus_offset() {
  brc "${tmp}/t.brc" 'def:7:[BMS] Battery Power:46' 'sample:1.5:7:-12.25' \
    'def:9:Odd "Name" 2:99' 'sample:2:9:3' 'sample:3:9:nan' 'sample:120.25:7:4.5'
  # 2026-05-24 20:10:53 PDT = 1779678653
  assert_eq "$(convert "${tmp}/t.brc")" <<'EOF'
car_bms_battery_power{unit="kW",trip="trip1"} -12.25 1779678654500
car_odd_name_2{unit="unknown_99",trip="trip1"} 3.0 1779678655000
car_bms_battery_power{unit="kW",trip="trip1"} 4.5 1779678773250
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
