#!/usr/bin/env python3
# Network probe, run hourly by net_probe.timer on secsvcs. Every run pings the pve2 and VPS
# paths, then runs, one at a time, each heavy test whose slot has come: the Ookla speed test,
# and iperf3 to websvcs (pve2, through pfSense's routing) and to the VPS (over Tailscale). A
# heavy test is due when its latest slot hour is after its last success, so a skipped one
# retries every hour until it succeeds or its next slot comes. It skips while VictoriaMetrics
# shows its path busy, so it neither disrupts real traffic nor reads it as a slow link.
# Results, skips and errors go to node_exporter's textfile collector; a probe never fails the
# unit. Standard library only.
# Usage:
#   /root/homelab-rendered/src/base/net_probe/net_probe.py

import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

rendered = Path("/root/homelab-rendered/src")
STATE = Path("/var/lib/net_probe/state.json")
METRICS = Path("/var/lib/node_exporter/textfile_collector/homelab_net_probe.prom")
VM_QUERY = "http://metrics.janedoe.com:8428/api/v1/query"
SPEEDTEST = "/usr/local/bin/speedtest"
DOWN_BPS = 1000 * 1e6
UP_BPS = 1000 * 1e6
TARGETS = {"pve2": "192.168.2.20", "vps": "100.64.0.2"}
# pfSense's WAN in Telegraf's net plugin, and pve2's uplink
WAN = 'interface="igc0"'
PVE2_NIC = 'host="pve2", device="eno1"'
# Heavy tests in run order (no f-strings with braces: this file is Jinja). slots: local hours, apart so one run never carries two of them.
# busy: (query in bit/s, limit) pairs; any series over its limit skips the test.
HEAVY = [
  # 21:00 catches the ISP's evening peak, 03:00 is the baseline
  {"probe": "speedtest", "slots": [3, 9, 15, 21], "busy": [
    ("rate(net_bytes_recv{" + WAN + "}[5m]) * 8", 0.3 * DOWN_BPS),
    ("rate(net_bytes_sent{" + WAN + "}[5m]) * 8", 0.3 * UP_BPS),
  ]},
  # A Moonlight stream from the gaming VM crosses pfSense too
  {"probe": "iperf_pve2", "path": "pve2", "slots": [1, 7, 13, 19], "busy": [
    ("rate(node_network_receive_bytes_total{" + PVE2_NIC + "}[5m]) * 8", 200e6),
    ("rate(node_network_transmit_bytes_total{" + PVE2_NIC + "}[5m]) * 8", 200e6),
  ]},
  # The reverse run is billed VPS egress, so once a day, when public traffic is negligible
  {"probe": "iperf_vps", "path": "vps", "slots": [4], "busy": []},
]
HELP = {
  "homelab_ping_loss_ratio": ("gauge", "Share of 20 pings to the path that got no reply."),
  "homelab_ping_rtt_seconds": ("gauge", "Average round trip of the replied pings."),
  "homelab_speedtest_bits_per_second": ("gauge", "Ookla speed test throughput; direction down is the download."),
  "homelab_isp_plan_bits_per_second": ("gauge", "The ISP plan's advertised speed (vars.yml isp)."),
  "homelab_speedtest_latency_seconds": ("gauge", "Ookla speed test idle latency."),
  "homelab_speedtest_jitter_seconds": ("gauge", "Ookla speed test idle jitter."),
  "homelab_speedtest_packet_loss_ratio": ("gauge", "Ookla speed test packet loss, when the server reports it."),
  "homelab_speedtest_info": ("gauge", "The last speed test's server and ISP."),
  "homelab_iperf_up": ("gauge", "1 when the path's iperf3 server answered, 0 when it was unreachable."),
  "homelab_iperf_bits_per_second": ("gauge", "iperf3 throughput as received; direction up is from secsvcs."),
  "homelab_iperf_retransmits": ("gauge", "TCP retransmits by the iperf3 sender."),
  "homelab_net_probe_last_attempt_timestamp_seconds": ("gauge", "Unix time the probe last ran or was skipped."),
  "homelab_net_probe_last_success_timestamp_seconds": ("gauge", "Unix time the probe last succeeded."),
  "homelab_net_probe_skipped_total": ("counter", "Probes skipped or failed, by reason."),
}


class Skip(Exception):
  """A probe that didn't measure: reason labels the skip, samples replace its last ones."""
  def __init__(self, reason, samples=None):
    super().__init__(reason)
    self.reason = reason
    self.samples = samples


class Tools:
  """The commands and the metrics query; tests substitute their own."""
  password = None

  def ping(self, address):
    """(loss ratio, average rtt in seconds or None) over 20 pings."""
    out = subprocess.run(["ping", "-c", "20", "-i", "0.2", "-W", "1", "-q", address], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60).stdout
    counts = re.search(r"(\d+) packets transmitted, (\d+) received", out)
    if not counts or not int(counts[1]):
      return 1.0, None
    rtt = re.search(r"= [\d.]+/([\d.]+)/", out)
    return 1 - int(counts[2]) / int(counts[1]), float(rtt[1]) / 1000 if rtt else None

  def speedtest(self):
    return json.loads(subprocess.run([SPEEDTEST, "--format=json", "--accept-license", "--accept-gdpr"],
                                     check=True, text=True, stdout=subprocess.PIPE, timeout=180).stdout)

  def iperf(self, address, reverse):
    """iperf3's JSON report; on failure it carries only an error."""
    command = ["iperf3", "-c", address, "-J", "-t", "10", "-O", "2", "--connect-timeout", "3000"]
    out = subprocess.run(command + (["-R"] if reverse else []), text=True, stdout=subprocess.PIPE,
                         timeout=60).stdout
    return json.loads(out)

  def query(self, expr):
    """The values of an instant query to VictoriaMetrics."""
    if self.password is None:
      self.password = subprocess.run([rendered / "base/podman/get_secret.sh", "victoriametrics_admin_password"],
                                     check=True, text=True, stdout=subprocess.PIPE).stdout.rstrip("\n")
    auth = base64.b64encode(f"admin:{self.password}".encode()).decode()
    request = urllib.request.Request(f"{VM_QUERY}?{urllib.parse.urlencode({'query': expr})}",
                                     headers={"Authorization": f"Basic {auth}"})
    with urllib.request.urlopen(request, timeout=10) as response:
      return [float(r["value"][1]) for r in json.load(response)["data"]["result"]]


def log(message):
  print(message, flush=True)


def latest_slot(now, hours):
  """Unix time of the latest slot hour at or before now, in local time."""
  local = datetime.fromtimestamp(now)
  past = [local.replace(hour=h, minute=0, second=0, microsecond=0) for h in hours if h <= local.hour]
  if not past:
    past = [(local - timedelta(days=1)).replace(hour=max(hours), minute=0, second=0, microsecond=0)]
  return max(past).timestamp()


def busy(tools, checks):
  for expr, limit in checks:
    try:
      values = tools.query(expr)
    except Exception as e:
      # A metrics outage shouldn't stop the measurements
      log(f"warning: busy check failed, testing anyway: {e}")
      return False
    if any(v > limit for v in values):
      return True
  return False


def speedtest(tools):
  r = tools.speedtest()
  samples = [
    ["homelab_speedtest_bits_per_second", {"direction": "down"}, r["download"]["bandwidth"] * 8],
    ["homelab_speedtest_bits_per_second", {"direction": "up"}, r["upload"]["bandwidth"] * 8],
    ["homelab_speedtest_latency_seconds", {}, r["ping"]["latency"] / 1000],
    ["homelab_speedtest_jitter_seconds", {}, r["ping"]["jitter"] / 1000],
    ["homelab_speedtest_info", {"server": f"{r['server']['name']} ({r['server']['location']})",
                                "isp": r["isp"]}, 1],
  ]
  if "packetLoss" in r:
    samples.append(["homelab_speedtest_packet_loss_ratio", {}, r["packetLoss"] / 100])
  return samples


def iperf(tools, path):
  samples = [["homelab_iperf_up", {"path": path}, 1]]
  for direction, reverse in (("up", False), ("down", True)):
    result = tools.iperf(TARGETS[path], reverse)
    error = result.get("error")
    if error and "busy" in error:
      raise Skip("server_busy")
    if error and "unable to connect" in error:
      raise Skip("unreachable", [["homelab_iperf_up", {"path": path}, 0]])
    if error:
      raise RuntimeError(error)
    labels = {"path": path, "direction": direction}
    samples.append(["homelab_iperf_bits_per_second", labels, result["end"]["sum_received"]["bits_per_second"]])
    samples.append(["homelab_iperf_retransmits", labels, result["end"]["sum_sent"].get("retransmits", 0)])
  return samples


def finish(state, probe, now, samples=None, skipped=None):
  s = state.setdefault(probe, {"skipped": {}})
  s["attempt"] = now
  if samples is not None:
    s["samples"] = samples
  if skipped:
    s["skipped"][skipped] = s["skipped"].get(skipped, 0) + 1
    log(f"{probe}: skipped, {skipped}")
  else:
    s["success"] = now


def write(path, text):
  path.parent.mkdir(parents=True, exist_ok=True)
  tmp = path.with_suffix(".tmp")
  tmp.write_text(text)
  tmp.chmod(0o644)
  tmp.replace(path)


def exposition(state):
  series = {"homelab_isp_plan_bits_per_second": [({"direction": "down"}, DOWN_BPS), ({"direction": "up"}, UP_BPS)]}
  for probe, s in sorted(state.items()):
    for name, labels, value in s.get("samples", []):
      series.setdefault(name, []).append((labels, value))
    series.setdefault("homelab_net_probe_last_attempt_timestamp_seconds", []).append(({"probe": probe}, s["attempt"]))
    if "success" in s:
      series.setdefault("homelab_net_probe_last_success_timestamp_seconds", []).append(({"probe": probe}, s["success"]))
    for reason, n in sorted(s["skipped"].items()):
      series.setdefault("homelab_net_probe_skipped_total", []).append(({"probe": probe, "reason": reason}, n))
  lines = []
  for name in HELP:
    if name not in series:
      continue
    kind, text = HELP[name]
    lines += [f"# HELP {name} {text}", f"# TYPE {name} {kind}"]
    for labels, value in series[name]:
      escaped = (v.replace("\\", "\\\\").replace('"', '\\"') for v in labels.values())
      label_text = ",".join(f'{k}="{v}"' for k, v in zip(labels, escaped))
      lines.append(name + ("{" + label_text + "}" if labels else "") + f" {value:.10g}")
  return "".join(f"{line}\n" for line in lines)


def run(now, state_path, metrics_path, tools):
  state = json.loads(state_path.read_text()) if state_path.exists() else {}
  reachable = {}
  for path, address in TARGETS.items():
    loss, rtt = tools.ping(address)
    reachable[path] = loss < 1
    samples = [["homelab_ping_loss_ratio", {"path": path}, loss]]
    if rtt is not None:
      samples.append(["homelab_ping_rtt_seconds", {"path": path}, rtt])
    finish(state, f"ping_{path}", now, samples, None if reachable[path] else "unreachable")

  for test in HEAVY:
    probe, path = test["probe"], test.get("path")
    if state.get(probe, {}).get("success", 0) >= latest_slot(now, test["slots"]):
      continue
    try:
      if path and not reachable[path]:
        raise Skip("unreachable", [["homelab_iperf_up", {"path": path}, 0]])
      if busy(tools, test["busy"]):
        raise Skip("busy")
      samples = iperf(tools, path) if path else speedtest(tools)
    except Skip as e:
      finish(state, probe, now, e.samples, e.reason)
    except Exception as e:
      log(f"{probe}: {e!r}")
      finish(state, probe, now, None, "error")
    else:
      finish(state, probe, now, samples)
      log(f"{probe}: ok")

  write(state_path, json.dumps(state, indent=1))
  write(metrics_path, exposition(state))


def main():
  os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"
  if len(sys.argv) != 1:
    sys.exit("usage: net_probe.py")
  run(time.time(), STATE, METRICS, Tools())


if __name__ == "__main__":
  main()
