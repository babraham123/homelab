#!/usr/bin/env python3
# Imports Car Scanner recordings (.brc) uploaded to copyparty's /car into VictoriaMetrics,
# at the samples' original timestamps. Each file is imported once, keyed by sha256 in the
# state file, so a re-upload adds nothing. Malformed files move to car/failed/; a trip
# older than VictoriaMetrics' retention stays where it is, recorded as too_old. The .brc
# files stay in copyparty as the long-term archive. Standard library only.
# The format is decoded in planning/copyparty/issues/03: .NET BinaryWriter output,
# little-endian, strings 7-bit-varint length-prefixed UTF-8. A header, then sensor
# definitions and samples interleaved, each behind a marker. Anything else fails the file.
# Usage:
#   src/nodes/websvcs/car_ingest.py         # car_ingest.timer
#   src/nodes/websvcs/car_ingest.py FILE    # prints FILE's import lines, or why it fails

import base64
import datetime
import hashlib
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zoneinfo
from collections import Counter
from pathlib import Path

rendered = Path("/root/homelab-rendered/src")
CAR = Path("/var/opt/copyparty/data/car")
# TSV: sha256, result, samples, unix time, file name
STATE = Path("/var/lib/car_ingest/state")
METRICS = Path("/var/lib/node_exporter/textfile_collector/car_ingest.prom")
URL = "https://metrics.janedoe.com/api/v1/import/prometheus"
# The phone's; recording start times are phone-local
TIMEZONE = "America/Los_Angeles"
RETENTION_DAYS = 14
RESULTS = ("ok", "failed", "too_old")

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
    try:
      value = self.data[self.pos:self.pos + length].decode("utf-8")
    except UnicodeDecodeError as e:
      raise BrcError(f"bad string at byte {self.pos}: {e}") from e
    self.pos += length
    return value

  def done(self):
    return self.pos == len(self.data)


def slug(name):
  return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def label(value):
  return value.replace("\\", "\\\\").replace('"', '\\"')


def parse(data, trip):
  """Returns the recording's samples as (series, value, ms) tuples; raises BrcError."""
  r = Reader(data)
  if r.string() != MAGIC:
    raise BrcError("not a Car Scanner recording")
  version = r.take("<i")
  if version != 2:
    raise BrcError(f"unsupported version {version}")
  for _ in ("vin", "car name", "car profile", "adapter"):
    r.string()
  # The top two bits of a .NET DateTime hold its Kind.
  ticks = r.take("<q") & 0x3FFFFFFFFFFFFFFF
  start = (DOTNET_EPOCH + datetime.timedelta(microseconds=ticks // 10)).replace(
    tzinfo=zoneinfo.ZoneInfo(TIMEZONE)).timestamp()

  sensors, samples = {}, []
  while not r.done():
    marker = r.take("<I")
    if marker == DEF_MARKER:
      sensor_id = r.take("<i")
      name = r.string()
      r.string()  # short name
      unit = r.take("<i")
      unit = label(UNITS.get(unit, f"unknown_{unit}"))
      # Concatenated: doubled braces in a format string would be Jinja's
      sensors[sensor_id] = "car_" + slug(name) + '{unit="' + unit + '",trip="' + label(trip) + '"}'
    elif marker == SAMPLE_MARKER:
      offset = r.take("<d")
      sensor_id = r.take("<i")
      value = r.take("<d")
      if sensor_id not in sensors:
        raise BrcError(f"sample for undefined sensor {sensor_id}")
      if math.isfinite(value):
        samples.append((sensors[sensor_id], value, round((start + offset) * 1000)))
    else:
      raise BrcError(f"unknown marker {marker:#010x} at byte {r.pos - 4}")
  if not samples:
    raise BrcError("no samples")
  return samples


def import_lines(samples):
  """VictoriaMetrics' import format: Prometheus text with millisecond timestamps."""
  return "".join(f"{series} {value!r} {ms}\n" for series, value, ms in samples)


def log(message, stream=sys.stdout):
  print(f"{datetime.datetime.now().astimezone().isoformat(timespec='seconds')} {message}", file=stream, flush=True)


def ingest(car, state, metrics, post, now):
  """Imports every settled .brc in car not yet in state. post(body) raises on failure,
  which stops the run before the file is recorded, so the next run retries it."""
  oldest_ms = (now - RETENTION_DAYS * 86400) * 1000
  (car / "failed").mkdir(parents=True, exist_ok=True)
  state.parent.mkdir(parents=True, exist_ok=True)
  state.touch()
  seen = {line.split("\t")[0] for line in state.read_text().splitlines()}

  def record(sha, result, samples, name):
    with state.open("a") as f:
      f.write(f"{sha}\t{result}\t{samples}\t{int(now)}\t{name}\n")
    seen.add(sha)
    log(f"{name}: {result} ({samples} samples)")

  for path in sorted(car.iterdir()):
    # Files modified in the last minute may still be uploading.
    if not path.is_file() or path.suffix.lower() != ".brc" or path.stat().st_mtime > now - 60:
      continue
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    if sha in seen:
      continue
    # The trip label is the file stem, Car Scanner's recording start.
    try:
      samples = parse(data, path.stem)
    except BrcError as e:
      log(f"{path.name}: {e}", sys.stderr)
      shutil.move(path, car / "failed" / path.name)
      record(sha, "failed", 0, path.name)
      continue
    # VictoriaMetrics silently drops samples outside its retention.
    if min(ms for _, _, ms in samples) < oldest_ms:
      record(sha, "too_old", len(samples), path.name)
      continue
    post(import_lines(samples).encode())
    record(sha, "ok", len(samples), path.name)

  counts = Counter(line.split("\t")[1] for line in state.read_text().splitlines())
  lines = ["# HELP car_ingest_files_total Car Scanner recordings processed, by outcome.",
           "# TYPE car_ingest_files_total counter"]
  lines += ['car_ingest_files_total{result="%s"} %d' % (r, counts[r]) for r in RESULTS]
  lines += ["# HELP car_ingest_last_success_timestamp_seconds Unix time of the last car_ingest run that completed.",
            "# TYPE car_ingest_last_success_timestamp_seconds gauge",
            f"car_ingest_last_success_timestamp_seconds {int(now)}"]
  # node_exporter only reads *.prom, so the rename is atomic for it.
  metrics.parent.mkdir(parents=True, exist_ok=True)
  tmp = metrics.with_suffix(".tmp")
  tmp.write_text("\n".join(lines) + "\n")
  tmp.chmod(0o644)
  tmp.replace(metrics)


def poster(password):
  auth = base64.b64encode(f"admin:{password}".encode()).decode()

  def post(body):
    request = urllib.request.Request(URL, data=body, headers={"Authorization": f"Basic {auth}"})
    for attempt in range(4):
      try:
        urllib.request.urlopen(request, timeout=120).close()
        return
      except urllib.error.HTTPError as e:
        if e.code < 500 or attempt == 3:
          raise
      except OSError:
        if attempt == 3:
          raise
      time.sleep(10)
  return post


def main():
  os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"
  if len(sys.argv) == 2:
    path = Path(sys.argv[1])
    try:
      sys.stdout.write(import_lines(parse(path.read_bytes(), path.stem)))
    except BrcError as e:
      sys.exit(f"{path}: {e}")
    return
  if len(sys.argv) != 1:
    sys.exit("usage: car_ingest.py [FILE]")
  password = subprocess.run([rendered / "base/podman/get_secret.sh", "victoriametrics_admin_password"],
                            check=True, text=True, stdout=subprocess.PIPE).stdout.rstrip("\n")
  if password in ("", "null"):
    sys.exit("secret victoriametrics_admin_password is empty")
  try:
    ingest(CAR, STATE, METRICS, poster(password), time.time())
  except OSError as e:
    sys.exit(f"stopped, the next run retries: {e}")


if __name__ == "__main__":
  main()
