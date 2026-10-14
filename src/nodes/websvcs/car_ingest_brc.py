#!/usr/bin/env python3
"""Prints a Car Scanner .brc recording as VictoriaMetrics import lines (Prometheus text
format with millisecond timestamps), one per sample:

    car_<sensor>{unit="...",trip="<TRIP>"} <value> <ms>

The format is decoded in planning/copyparty/issues/03: .NET BinaryWriter output,
little-endian, strings 7-bit-varint length-prefixed UTF-8. A header, then sensor
definitions and samples interleaved, each behind a marker. Exits 1 on anything else, so
car_ingest.sh can move the file to failed/.

Usage:
  car_ingest_brc.py FILE TRIP TIMEZONE
"""

import datetime
import math
import re
import struct
import sys
import zoneinfo

MAGIC = "CARSCANNERRECORD"
DEF_MARKER = 0x00D56190
SAMPLE_MARKER = 0x01274350
# Car Scanner's unit enum; values are SI whatever the app displays.
UNITS = {
    0: "none", 3: "km", 6: "rpm", 10: "V", 14: "%", 15: "°C", 17: "s", 18: "min",
    27: "kOhm", 30: "Hz", 46: "kW", 54: "h", 58: "currency", 59: "A", 60: "kWh",
    61: "Wh", 62: "Ah", 63: "hours",
}
DOTNET_EPOCH = datetime.datetime(1, 1, 1)


class BrcError(Exception):
    pass


class Reader:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def take(self, fmt):
        size = struct.calcsize(fmt)
        if self.pos + size > len(self.data):
            raise BrcError(f"truncated at byte {self.pos}")
        value = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return value[0]

    def string(self):
        length, shift = 0, 0
        while True:
            byte = self.take("<B")
            length |= (byte & 0x7F) << shift
            shift += 7
            if not byte & 0x80:
                break
        if self.pos + length > len(self.data):
            raise BrcError(f"truncated string at byte {self.pos}")
        value = self.data[self.pos:self.pos + length].decode("utf-8")
        self.pos += length
        return value

    def done(self):
        return self.pos == len(self.data)


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def label(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def convert(data, trip, timezone):
    r = Reader(data)
    if r.string() != MAGIC:
        raise BrcError("not a Car Scanner recording")
    version = r.take("<i")
    if version != 2:
        raise BrcError(f"unsupported version {version}")
    for _ in ("vin", "car name", "car profile", "adapter"):
        r.string()
    # The top two bits of a .NET DateTime hold its Kind; the start is phone-local.
    ticks = r.take("<q") & 0x3FFFFFFFFFFFFFFF
    start = (DOTNET_EPOCH + datetime.timedelta(microseconds=ticks // 10)).replace(
        tzinfo=zoneinfo.ZoneInfo(timezone)).timestamp()

    sensors = {}
    trip = label(trip)
    while not r.done():
        marker = r.take("<I")
        if marker == DEF_MARKER:
            sensor_id = r.take("<i")
            name = r.string()
            r.string()  # short name
            unit = r.take("<i")
            sensors[sensor_id] = 'car_{}{{unit="{}",trip="{}"}}'.format(
                slug(name), label(UNITS.get(unit, f"unknown_{unit}")), trip)
        elif marker == SAMPLE_MARKER:
            offset = r.take("<d")
            sensor_id = r.take("<i")
            value = r.take("<d")
            if sensor_id not in sensors:
                raise BrcError(f"sample for undefined sensor {sensor_id}")
            if math.isfinite(value):
                yield f"{sensors[sensor_id]} {value!r} {round((start + offset) * 1000)}"
        else:
            raise BrcError(f"unknown marker {marker:#010x} at byte {r.pos - 4}")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.split("Usage:")[1].strip())
    path, trip, timezone = sys.argv[1:]
    with open(path, "rb") as f:
        data = f.read()
    try:
        lines = list(convert(data, trip, timezone))
    except (BrcError, UnicodeDecodeError) as e:
        sys.exit(f"{path}: {e}")
    if not lines:
        sys.exit(f"{path}: no samples")
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
