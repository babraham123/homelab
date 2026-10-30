# shellcheck shell=bash
# src/base/vm_watchdog/vm_watchdog.py against docs/services.md's "VM watchdog": a VM is reset
# once its agent, having answered, is silent for 3 minutes in which the guest is also quiet,
# or for an hour while it is busy; never if its agent never answered or isn't enabled; not
# while the host or the VM is on hold, with its silence starting over afterwards; at most 3
# times in 6 hours. Checks run every 30 seconds.
# shellcheck source=tests/lib.sh
source tests/lib.sh

# Runs the watchdog against one VM (101, router) from t=0 to t=$1 seconds and prints the
# times it reset the VM. The Python on stdin overrides any of: up(t) (the agent answers),
# activity(t), hold(t) (the host's reason to hold off), vm_hold(t), pid(t), agent.
simulate() {
  python3 -I -B -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vm_watchdog", "src/base/vm_watchdog/vm_watchdog.py")
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
w.log = lambda *args, **kwargs: None
agent = True
def up(t): return True
def activity(t): return 0
def hold(t): return None
def vm_hold(t): return None
def pid(t): return 1000
exec(sys.stdin.read())

class Host:
  t = 0
  resets = []
  def survey(self):
    if hold(self.t):
      return hold(self.t), []
    return None, [w.Guest("101", "router", pid(self.t), agent, vm_hold(self.t), activity(self.t))]
  def ping(self, vmid): return up(self.t)
  def reset(self, vmid):
    self.resets.append(self.t)
    return True

host = Host()
watchdog = w.Watchdog(host)
for t in range(0, int(sys.argv[1]) + 1, w.INTERVAL):
  host.t = t
  watchdog.check(t)
print(*host.resets)
print(watchdog.metrics(0), end="", file=sys.stderr)
' "$1"
}

test_resets_a_frozen_quiet_guest_after_3_minutes() {
  # Silent from 300, quiet throughout
  assert_eq "$(simulate 1200 <<< 'def up(t): return t < 300')" <<< "480"
}

test_busy_guest_waits_an_hour_or_until_it_goes_quiet() {
  assert_eq "$(simulate 4000 <<< '
def up(t): return t < 300
def activity(t): return t')" <<< "3900"
  # Busy until 1000: the first check that sees it quiet is 1020, 3 minutes later is 1200
  assert_eq "$(simulate 4000 <<< '
def up(t): return t < 300
def activity(t): return min(t, 1000)')" <<< "1200"
}

test_never_resets_without_an_agent_that_answered() {
  assert_eq "$(simulate 7200 <<< 'def up(t): return False')" <<< ""
  assert_eq "$(simulate 7200 <<< '
agent = False
def up(t): return t < 300')" <<< ""
  # Restarted at 420 (a new QEMU pid) and its agent hasn't answered since
  assert_eq "$(simulate 7200 <<< '
def up(t): return t < 300
def pid(t): return 1000 if t < 420 else 2000')" <<< ""
}

test_holds_restart_the_silence() {
  # Silent from 300; held from 200 to 2000, so silent again from the 2010 check
  assert_eq "$(simulate 4000 <<< '
def up(t): return t < 300
def hold(t): return "backup_orchestrator.service activating" if 200 <= t < 2000 else None')" <<< "2190"
  assert_eq "$(simulate 4000 <<< '
def up(t): return t < 300
def vm_hold(t): return "lock backup" if 200 <= t < 2000 else None')" <<< "2190"
}

test_gives_up_after_3_resets_in_6_hours() {
  # Answers for the first minute of every 10, silent and quiet after
  assert_eq "$(simulate 7000 <<< 'def up(t): return t % 600 < 60')" <<< "240 840 1440"
  assert_eq "$(simulate 7000 2>&1 > /dev/null <<< 'def up(t): return t % 600 < 60' | grep '^homelab_vm_watchdog_[a-z_]*{')" <<EOF
homelab_vm_watchdog_agent_up{vmid="101",name="router"} 0
homelab_vm_watchdog_resets_total{vmid="101",name="router"} 3
homelab_vm_watchdog_gave_up{vmid="101",name="router"} 1
EOF
}

test_pause_by_hand_expires() {
  assert_eq "$(python3 -I -B -c '
import importlib.util, sys, time
from pathlib import Path
spec = importlib.util.spec_from_file_location("vm_watchdog", "src/base/vm_watchdog/vm_watchdog.py")
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
w.PAUSE_FILE = Path(sys.argv[1]) / "pause_until"
w.main(["pause", "5"])
print(w.pause_reason() is not None)
w.main(["resume"])
print(w.pause_reason())
w.PAUSE_FILE.write_text(str(time.time() - 1))
print(w.pause_reason())
' "$tmp" | sed 's/until [0-9:]*/until HH:MM/')" <<EOF
paused by hand until HH:MM
True
vm_watchdog resumed
None
None
EOF
}
