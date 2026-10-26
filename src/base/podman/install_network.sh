#!/bin/bash
# Creates the container network. On the VMs, also resets ufw to the base rules and lets
# Traefik's traffic through to its container: Podman writes its own iptables rules, so
# routed traffic needs a ufw rule naming the network's interface. vpnsvcs keeps the rules
# from its guide and publishes nothing.
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

if [[ "$node" != vpnsvcs ]]; then
  POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
  NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')
  ufw route allow in on "$NET_IFACE" out on "$POD_IFACE" to any port 80,443 proto tcp
  # Image builds (build.sh) run on Podman's default network and fetch packages: DNS, plus HTTP
  # for Debian's apt mirrors
  BUILD_IFACE=$(podman network inspect podman | jq -r '.[0].network_interface')
  ufw route allow in on "$BUILD_IFACE" out on "$NET_IFACE" to any port 53
  ufw route allow in on "$BUILD_IFACE" out on "$NET_IFACE" to any port 80,443 proto tcp
  ufw --force enable
  ufw status verbose
fi
