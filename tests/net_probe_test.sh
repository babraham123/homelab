# shellcheck shell=bash
# src/base/net_probe/net_probe.py.j2 against planning/hardware-monitoring/issues/03 and 04:
# pings both paths every run, before any heavy test; heavy tests run one at a time in the
# order speed test, pve2 iperf3, VPS iperf3, each both ways, only when their latest slot
# (speed test 03/09/15/21, pve2 01/07/13/19, VPS 04) is after their last success, so once
# per slot; a busy path or a busy iperf3 server skips the test until the next hourly run;
# a failed busy check tests anyway; pve2 not answering pings skips its iperf3 untried and
# records it down; skips and errors never fail the run; the textfile keeps each probe's
# last results between runs and carries the plan speed.
# shellcheck source=tests/lib.sh
source tests/lib.sh

render_script() {
  cat > "${tmp}/vars.yml" <<EOF
site: {url: example.com}
isp: {down_mbps: 1000, up_mbps: 100}
websvcs: {ip: 192.168.2.20}
vpnsvcs: {tailnet_ip: 100.64.0.2}
EOF
  jinjanate --quiet src/base/net_probe/net_probe.py.j2 "${tmp}/vars.yml" > "${tmp}/net_probe.py"
}

# Usage: probe HH:MM [FAULT...]; one run at that time on 2026-10-24 (UTC), with state in
# $tmp/state.json and the textfile at $tmp/prom. Prints the calls it made, one per line.
# FAULT: pve2_off, wan_busy, pve2_busy, query_down, vps_server_busy, speedtest_fails
probe() {
  [ -f "${tmp}/net_probe.py" ] || render_script
  TZ=UTC python3 -I - "$tmp" "$@" <<'EOF'
import calendar, importlib.util, pathlib, sys
tmp, at, faults = pathlib.Path(sys.argv[1]), sys.argv[2], set(sys.argv[3:])
spec = importlib.util.spec_from_file_location("net_probe", tmp / "net_probe.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.log = lambda message: None
names = {"192.168.2.20": "pve2", "100.64.0.2": "vps"}

class Fake:
  def ping(self, address):
    print(f"ping {names[address]}")
    return (1.0, None) if names[address] == "pve2" and "pve2_off" in faults else (0.0, 0.002)

  def query(self, expr):
    target = "wan" if "net_bytes" in expr else "pve2"
    print(f"busy {target}")
    if "query_down" in faults:
      raise OSError("connection refused")
    return [5e8 if f"{target}_busy" in faults else 1e6]

  def speedtest(self):
    print("speedtest")
    if "speedtest_fails" in faults:
      raise RuntimeError("no servers")
    return {"download": {"bandwidth": 1e8}, "upload": {"bandwidth": 1.25e7},
            "ping": {"latency": 9.5, "jitter": 1.5}, "packetLoss": 0,
            "server": {"name": "Sonic", "location": "San Jose, CA"}, "isp": 'AT"T'}

  def iperf(self, address, reverse):
    path = names[address]
    print(f"iperf {path} {'down' if reverse else 'up'}")
    if path == "vps" and "vps_server_busy" in faults:
      return {"error": "the server is busy running a test. try again later"}
    rate = {"pve2": 9e8, "vps": 2e8}[path] / (2 if reverse else 1)
    return {"end": {"sum_received": {"bits_per_second": rate}, "sum_sent": {"retransmits": 3}}}

now = calendar.timegm((2026, 10, 24, *map(int, at.split(":")), 0))
m.run(now, tmp / "state.json", tmp / "prom", Fake())
EOF
}

# The textfile's samples for METRIC (an extended regex), without HELP and TYPE
samples() {
  grep -E "^$1[{ ]" "${tmp}/prom" || true
}

test_first_run_pings_then_runs_every_test_in_order() {
  assert_eq "$(probe 03:05)" <<EOF
ping pve2
ping vps
busy wan
busy wan
speedtest
busy pve2
busy pve2
iperf pve2 up
iperf pve2 down
iperf vps up
iperf vps down
EOF
  assert_eq "$(samples homelab_speedtest_bits_per_second)" <<EOF
homelab_speedtest_bits_per_second{direction="down"} 800000000
homelab_speedtest_bits_per_second{direction="up"} 100000000
EOF
  assert_eq "$(samples homelab_speedtest_info)" <<EOF
homelab_speedtest_info{server="Sonic (San Jose, CA)",isp="AT\"T"} 1
EOF
  assert_eq "$(samples homelab_iperf_bits_per_second)" <<EOF
homelab_iperf_bits_per_second{path="pve2",direction="up"} 900000000
homelab_iperf_bits_per_second{path="pve2",direction="down"} 450000000
homelab_iperf_bits_per_second{path="vps",direction="up"} 200000000
homelab_iperf_bits_per_second{path="vps",direction="down"} 100000000
EOF
  assert_eq "$(samples homelab_isp_plan_bits_per_second)" <<EOF
homelab_isp_plan_bits_per_second{direction="down"} 1000000000
homelab_isp_plan_bits_per_second{direction="up"} 100000000
EOF
  assert_eq "$(samples homelab_ping_rtt_seconds)" <<EOF
homelab_ping_rtt_seconds{path="pve2"} 0.002
homelab_ping_rtt_seconds{path="vps"} 0.002
EOF
}

test_each_test_runs_once_per_slot_and_keeps_its_results() {
  probe 03:05 > /dev/null
  # 04:00 is the VPS's slot; the speed test (03:00) and pve2 (01:00) already succeeded since
  assert_eq "$(probe 04:05)" <<EOF
ping pve2
ping vps
iperf vps up
iperf vps down
EOF
  assert_eq "$(probe 05:05)" <<EOF
ping pve2
ping vps
EOF
  assert_eq "$(probe 07:05 | grep -c iperf)" <<< 2
  [ -n "$(samples homelab_speedtest_bits_per_second)" ] || flunk "dropped the 03:05 speed test"
}

test_busy_wan_defers_the_speed_test_to_the_next_hour() {
  probe 03:05 wan_busy | grep -q speedtest && flunk "tested a busy WAN"
  assert_eq "$(samples homelab_net_probe_skipped_total)" <<EOF
homelab_net_probe_skipped_total{probe="speedtest",reason="busy"} 1
EOF
  probe 04:05 | grep -q speedtest || flunk "no retry an hour later"
  # 04:05 succeeded, so the 03:00 slot is done
  probe 05:05 | grep -q speedtest && flunk "ran twice in one slot"
  true
}

test_busy_pve2_skips_only_its_test() {
  assert_eq "$(probe 03:05 pve2_busy | grep -E 'iperf|speedtest')" <<EOF
speedtest
iperf vps up
iperf vps down
EOF
}

test_failed_busy_check_tests_anyway() {
  probe 03:05 query_down | grep -q speedtest || flunk "skipped on a failed busy check"
}

test_pve2_off_skips_its_iperf_untried_and_marks_it_down() {
  probe 03:05 > /dev/null
  probe 07:05 pve2_off | grep -q "iperf pve2" && flunk "tried pve2 while it doesn't answer"
  assert_eq "$(samples 'homelab_iperf_(up|bits_per_second)' | grep pve2)" <<EOF
homelab_iperf_up{path="pve2"} 0
EOF
  assert_eq "$(samples homelab_ping_loss_ratio)" <<EOF
homelab_ping_loss_ratio{path="pve2"} 1
homelab_ping_loss_ratio{path="vps"} 0
EOF
}

test_busy_server_and_failures_retry_without_failing_the_run() {
  probe 03:05 vps_server_busy speedtest_fails > /dev/null
  assert_eq "$(samples homelab_net_probe_skipped_total)" <<EOF
homelab_net_probe_skipped_total{probe="iperf_vps",reason="server_busy"} 1
homelab_net_probe_skipped_total{probe="speedtest",reason="error"} 1
EOF
  assert_eq "$(probe 04:05 | grep -E 'iperf|speedtest')" <<EOF
speedtest
iperf vps up
iperf vps down
EOF
}
