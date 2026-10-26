# shellcheck shell=bash
# src/base/net_probe/config.json.j2 against planning/hardware-monitoring/issues/03 and 04:
# targets websvcs (pve2) and the VPS's tailnet address; heavy tests in the order speed test,
# pve2 iperf3, VPS iperf3, with slots 03/09/15/21, 01/07/13/19 and 04; the speed test is
# busy over 30% of the ISP plan either way on pfSense's WAN, pve2 over 200 Mbit/s on its
# NICs, the VPS never; the textfile keeps its homelab_net_probe.prom name. The probe's own
# behavior is tested in github.com/babraham123/net-probe.
# shellcheck source=tests/lib.sh
source tests/lib.sh

# Prints the config rendered for an ISP plan of 1000 down, 100 up, through FILTER (Python
# that sees the parsed config as c)
config() {
  cat > "${tmp}/vars.yml" <<EOF
site: {url: example.com}
isp: {down_mbps: 1000, up_mbps: 100}
websvcs: {ip: 192.168.2.20}
vpnsvcs: {tailnet_ip: 100.64.0.2}
EOF
  jinjanate --quiet src/base/net_probe/config.json.j2 "${tmp}/vars.yml" > "${tmp}/config.json"
  python3 -I -c "import json, sys
c = json.load(open(sys.argv[1]))
$1" "${tmp}/config.json"
}

test_targets_and_textfile() {
  assert_eq "$(config 'print(c["targets"], c["metrics_path"])')" <<EOF
{'pve2': '192.168.2.20', 'vps': '100.64.0.2'} /var/lib/node_exporter/textfile_collector/homelab_net_probe.prom
EOF
  assert_eq "$(config 'print(c["victoriametrics"]["query_url"])')" <<EOF
https://metrics.example.com/api/v1/query
EOF
}

test_heavy_tests_slots_and_busy_limits() {
  assert_eq "$(config 'for t in c["tests"]: print(t["test"], t.get("path", "-"), t["slots"], [b["limit_bps"] for b in t.get("busy", [])])')" <<EOF
speedtest - [3, 9, 15, 21] [300000000, 30000000]
iperf pve2 [1, 7, 13, 19] [200000000, 200000000]
iperf vps [4] []
EOF
}
