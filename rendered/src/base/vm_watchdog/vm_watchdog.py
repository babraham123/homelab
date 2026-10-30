#!/usr/bin/env python3
# Resets a VM on this Proxmox host that froze: its guest agent answered after the VM started,
# then stopped answering, and the guest has sent no network traffic and done no disk I/O for
# QUIET. A guest still busy without its agent (a reboot, an update) is reset only after
# MAX_SILENT. A VM whose agent never answered is left alone: no agent installed, or still
# booting.
# Nothing is reset while the host is on hold: paused by hand, a backup run, vzdump, a package
# upgrade (it swaps out the Perl modules qm and pvesh load), or pve-guests starting or stopping
# the guests. Nor is a VM that is locked, paused by QEMU or the target of a running task
# (start, stop, shutdown, snapshot, migrate). A VM's silence starts over once a hold ends.
# Writes node_exporter textfile metrics for the VMWatchdog* alerts. Standard library only.
# Usage:
#   /root/homelab-rendered/src/base/vm_watchdog/vm_watchdog.py                  the service
#   /root/homelab-rendered/src/base/vm_watchdog/vm_watchdog.py pause [MINUTES]  default 120
#   /root/homelab-rendered/src/base/vm_watchdog/vm_watchdog.py resume
# Ref:
#   https://pve.proxmox.com/pve-docs/qm.1.html
#   https://pve.proxmox.com/pve-docs/api-viewer/ (nodes/{node}/qemu/{vmid}/status/current)

import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

INTERVAL = 30
# Agent silence that resets a guest that has also been quiet as long; a frozen guest sends
# nothing and does no I/O, while one rebooting or installing updates does both
QUIET = 180
# Agent silence that resets a guest even while it is busy, e.g. hung with only its disk
# writes still going
MAX_SILENT = 3600
# Resets per VM within RESET_WINDOW; past that it is left to the VMWatchdogGaveUp alert
MAX_RESETS = 3
RESET_WINDOW = 6 * 3600
PAUSE_MINUTES = 120
# On tmpfs, so a host reboot ends a pause
PAUSE_FILE = Path("/run/vm_watchdog/pause_until")
METRICS = Path("/var/lib/node_exporter/textfile_collector/homelab_vm_watchdog.prom")
# A oneshot unit is activating while it runs; pve-guests is activating while it starts the
# guests at boot and deactivating while it shuts them down
HOLD_UNITS = ["backup_orchestrator.service", "pve-guests.service"]
# unattended-upgr is unattended-upgrades, cut to the kernel's 15-character comm
HOLD_PROCESSES = {"apt", "apt-get", "aptitude", "dpkg", "unattended-upgr", "vzdump"}
os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"


def log(message, stream=sys.stdout):
  print(f"{datetime.now().astimezone().isoformat(timespec='seconds')} {message}", file=stream, flush=True)


def run(args, timeout, check=True):
  """The command's stdout, or None if it failed or timed out."""
  try:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=check).stdout
  except (subprocess.SubprocessError, OSError):
    return None


@dataclass
class Guest:
  vmid: str
  name: str
  pid: int | None  # QEMU's; a new one means the VM was restarted
  agent: bool  # the guest agent is enabled in the VM's config
  hold: str | None  # why the VM is left alone this round
  activity: int  # bytes the guest has sent, read and written; frozen, it stops growing


@dataclass
class State:
  name: str = ""
  pid: int | None = None  # the QEMU pid the agent answered under: armed while it matches
  agent_up: int | None = None  # the last ping; None while the VM is held
  silent_since: float | None = None
  samples: list = field(default_factory=list)  # (time, activity) since silent_since
  resets: list = field(default_factory=list)  # times, within RESET_WINDOW
  resets_total: int = 0
  gave_up: bool = False

  def hear(self):
    self.silent_since, self.samples = None, []


def pause_reason():
  try:
    until = float(PAUSE_FILE.read_text())
  except (OSError, ValueError):
    return None
  if until <= time.time():
    return None
  return f"paused by hand until {datetime.fromtimestamp(until):%H:%M}"


class Proxmox:
  def __init__(self):
    self.node = socket.gethostname().split(".")[0]

  def pvesh(self, path, *args):
    out = run(["pvesh", "get", path, "--output-format", "json", *args], 60)
    if out is None:
      raise RuntimeError(f"pvesh get {path} failed")
    return json.loads(out)

  def host_hold(self, tasks):
    states = (run(["systemctl", "is-active", *HOLD_UNITS], 30, check=False) or "").split()
    for unit, state in zip(HOLD_UNITS, states):
      if state in ("activating", "deactivating"):
        return f"{unit} {state}"
    for comm in Path("/proc").glob("[0-9]*/comm"):
      try:
        name = comm.read_text().strip()
      except OSError:
        continue
      if name in HOLD_PROCESSES:
        return f"{name} running"
    # A backup of any one VM loads the host's disks enough to slow every agent
    if any(t["type"] == "vzdump" for t in tasks):
      return "vzdump task running"
    return None

  def survey(self):
    """Why the whole host is on hold, or None and its running VMs."""
    reason = pause_reason()
    if reason:
      return reason, []
    tasks = [t for t in self.pvesh(f"/nodes/{self.node}/tasks", "--source", "active")
             if not t.get("endtime")]
    reason = self.host_hold(tasks)
    if reason:
      return reason, []
    on_vm = {str(t.get("id")): t["type"] for t in tasks}
    guests = []
    for vm in self.pvesh(f"/nodes/{self.node}/qemu"):
      if vm.get("status") != "running":
        continue
      vmid = str(vm["vmid"])
      status = self.pvesh(f"/nodes/{self.node}/qemu/{vmid}/status/current")
      qmp = status.get("qmpstatus")
      # A hung QEMU reports no qmpstatus at all, and that is no reason to hold off
      if status.get("lock"):
        hold = f"lock {status['lock']}"
      elif vmid in on_vm:
        hold = f"task {on_vm[vmid]}"
      elif qmp and qmp != "running":
        hold = f"QEMU {qmp}"
      else:
        hold = None
      guests.append(Guest(vmid, status.get("name", vmid), status.get("pid"),
                          bool(int(status.get("agent") or 0)), hold,
                          sum(int(status.get(k) or 0) for k in ("netout", "diskread", "diskwrite"))))
    return None, guests

  def ping(self, vmid):
    return run(["qm", "guest", "cmd", vmid, "ping"], 30) is not None

  def reset(self, vmid):
    # Stop and start rather than qm reset: a new QEMU process also clears a wedged QEMU or
    # passed-through device, and the start runs the hookscript (pve2's GPU handover)
    return run(["qm", "stop", vmid], 120) is not None and run(["qm", "start", vmid], 240) is not None


class Watchdog:
  def __init__(self, host):
    self.host = host
    self.states = {}
    self.hold = None

  def check(self, now):
    hold, guests = self.host.survey()
    if hold != self.hold:
      log(f"holding off: {hold}" if hold else "holding off ended")
      self.hold = hold
    watched = set()
    for guest in guests:
      if not guest.agent:
        continue
      watched.add(guest.vmid)
      state = self.states.setdefault(guest.vmid, State())
      state.name = guest.name
      if guest.pid != state.pid:
        state.pid = None
      if guest.hold:
        state.agent_up = None
        state.hear()
        continue
      self.watch(now, guest, state)
    for vmid, state in self.states.items():
      if vmid not in watched:
        state.agent_up = None
        state.hear()

  def watch(self, now, guest, state):
    label = f"VM {guest.vmid} ({guest.name})"
    if self.host.ping(guest.vmid):
      if state.silent_since is not None:
        log(f"{label}: agent answering again after {now - state.silent_since:.0f}s")
      state.pid, state.agent_up, state.gave_up = guest.pid, 1, False
      state.hear()
      return
    state.agent_up = 0
    if state.pid is None:
      return
    if state.silent_since is None:
      log(f"{label}: agent silent")
      state.silent_since = now
    # samples[0] is the newest sample at least QUIET old, once there is one
    state.samples.append((now, guest.activity))
    while len(state.samples) > 1 and state.samples[1][0] <= now - QUIET:
      state.samples.pop(0)
    since, activity = state.samples[0]
    quiet = now - since >= QUIET and guest.activity == activity
    silent = now - state.silent_since
    if not quiet and silent < MAX_SILENT:
      return
    state.resets = [t for t in state.resets if t > now - RESET_WINDOW]
    if len(state.resets) >= MAX_RESETS:
      if not state.gave_up:
        log(f"{label}: frozen, but already reset {MAX_RESETS} times in {RESET_WINDOW // 3600}h; leaving it", sys.stderr)
        state.gave_up = True
      return
    log(f"{label}: agent silent {silent:.0f}s, guest {'quiet' if quiet else 'still busy'}; resetting")
    state.resets.append(now)
    state.resets_total += 1
    state.pid = None
    state.hear()
    if not self.host.reset(guest.vmid):
      log(f"{label}: reset failed", sys.stderr)

  def metrics(self, wall):
    def series(name, kind, help, values):
      return [f"# HELP {name} {help}", f"# TYPE {name} {kind}", *(f"{name}{labels} {value}" for labels, value in values)]

    labeled = [(f'{{vmid="{vmid}",name="{s.name}"}}', s) for vmid, s in sorted(self.states.items())]
    return "\n".join([
        *series("homelab_vm_watchdog_last_check_timestamp_seconds", "gauge",
                "Unix time of vm_watchdog's last completed check.", [("", int(wall))]),
        *series("homelab_vm_watchdog_on_hold", "gauge",
                "1 while the host is paused or busy and no VM is checked.", [("", int(self.hold is not None))]),
        *series("homelab_vm_watchdog_agent_up", "gauge",
                "1 if the VM's guest agent answered the last ping.",
                [(labels, s.agent_up) for labels, s in labeled if s.agent_up is not None]),
        *series("homelab_vm_watchdog_resets_total", "counter",
                "VM resets since vm_watchdog started.", [(labels, s.resets_total) for labels, s in labeled]),
        *series("homelab_vm_watchdog_gave_up", "gauge",
                "1 once a frozen VM has used up its resets and is left as it is.",
                [(labels, int(s.gave_up)) for labels, s in labeled]),
    ]) + "\n"


def write_metrics(text):
  METRICS.parent.mkdir(parents=True, exist_ok=True)
  tmp = METRICS.with_suffix(".tmp")
  tmp.write_text(text)
  tmp.chmod(0o644)
  # node_exporter only reads *.prom, and the rename is atomic
  tmp.replace(METRICS)


def main(args):
  match args:
    case []:
      watch()
    case ["pause", *minutes] if len(minutes) <= 1:
      PAUSE_FILE.parent.mkdir(parents=True, exist_ok=True)
      PAUSE_FILE.write_text(str(time.time() + int(minutes[0] if minutes else PAUSE_MINUTES) * 60))
      print(pause_reason())
    case ["resume"]:
      PAUSE_FILE.unlink(missing_ok=True)
      print("vm_watchdog resumed")
    case _:
      sys.exit(f"unknown command: {' '.join(args)}")


def watch():
  stopping = threading.Event()
  # Finishes the check under way, a reset included; systemd's KillMode=mixed leaves its qm
  # calls running
  signal.signal(signal.SIGTERM, lambda *_: stopping.set())
  watchdog = Watchdog(Proxmox())
  log("watching")
  while True:
    try:
      watchdog.check(time.monotonic())
      write_metrics(watchdog.metrics(time.time()))
    except Exception as e:  # a failed survey resets nothing, and the next one may pass
      log(f"check failed: {e}", sys.stderr)
    if stopping.wait(INTERVAL):
      return


if __name__ == "__main__":
  main(sys.argv[1:])
