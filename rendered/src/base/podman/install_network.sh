#!/bin/bash
# Creates the container network. On the VMs, also resets ufw to the base rules and lets
# Traefik's traffic through to its container: Podman writes its own iptables rules, so
# routed traffic needs a ufw rule naming the network's interface. vpnsvcs keeps the rules
# from its guide and publishes nothing; it gets only the image builds' egress. Every node
# gets its open_ports.
# Usage:
#   /root/homelab-rendered/src/base/podman/install_network.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root
node=$(hostname -s)

if [[ "$node" != vpnsvcs ]]; then
  ufw --force reset
  # SSH, HTTP
  ufw allow in from any to any port 22,80,443 proto tcp
  # mDNS
  ufw allow in from any to any port 5353 proto udp
fi

install_quadlet "${rendered}/nodes/${node}/net.network"
systemctl daemon-reload
systemctl start net-network

NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')
POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
if [[ "$node" != vpnsvcs ]]; then
  ufw route allow in on "$NET_IFACE" out on "$POD_IFACE" to any port 80,443 proto tcp
  # Netavark's nftables rules accept container traffic in their own table, which doesn't
  # override ufw's drops: DNS to aardvark-dns on the bridge gateway, and egress
  ufw allow in on "$POD_IFACE" to any port 53
  ufw route allow in on "$POD_IFACE" out on "$NET_IFACE"
fi
# Ports ufw opens on the host, each to its sources (open_ports in the inventory): the
# exporters its vmagent scrapes through the bridge gateway, iperf3 for secsvcs's net_probe
case $node in
  vpnsvcs)
    ufw allow in on "$POD_IFACE" from 10.13.0.7 to any port 8405 proto tcp
    ufw allow in on "$POD_IFACE" from 10.13.0.7 to any port 9090 proto tcp
    ufw allow in on "$POD_IFACE" from 10.13.0.7 to any port 60601 proto tcp
    ;;
  websvcs)
    ufw allow in from 192.168.4.20 to any port 5201 proto tcp
    ufw allow in on "$POD_IFACE" from 10.11.0.7 to any port 9633 proto tcp
    ufw allow in on "$POD_IFACE" from 10.11.0.7 to any port 9835 proto tcp
    ;;
esac
# Image builds (build.sh) run on Podman's default network and fetch packages: DNS, plus HTTP
# for Debian's apt mirrors
BUILD_IFACE=$(podman network inspect podman | jq -r '.[0].network_interface')
ufw route allow in on "$BUILD_IFACE" out on "$NET_IFACE" to any port 53
ufw route allow in on "$BUILD_IFACE" out on "$NET_IFACE" to any port 80,443 proto tcp
if [[ "$node" != vpnsvcs ]]; then
  ufw --force enable
  ufw status verbose
fi
