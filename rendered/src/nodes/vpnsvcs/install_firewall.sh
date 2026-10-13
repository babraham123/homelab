#!/bin/bash
# Replaces the ufw rules with the public endpoint's: deny by default, public SSH, HTTP(S)
# and Headscale in, and only the service VMs' HTTP(S) out over the tailnet. ufw rules
# match in order, so the allows stand in for Tailscale ACLs.
# Leaves ufw disabled: add the permanent rules to /etc/ufw/before.rules, then enable it.
# Usage:
#   /root/homelab-rendered/src/nodes/vpnsvcs/install_firewall.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')

# Clamp MSS until before.rules makes it permanent
iptables -t mangle -A FORWARD -i tailscale0 -o "$NET_IFACE" -p tcp -m tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

ufw --force reset
ufw default deny incoming
ufw default deny outgoing
ufw allow out 53
ufw allow out on "$NET_IFACE"
ufw allow in from any to any port 2202,80,443 proto tcp
ufw allow in from any to any port 3478,41641 proto udp
ufw allow out on tailscale0 from any to 192.168.4.20 port 80,443 proto tcp
ufw allow out on tailscale0 from any to 192.168.4.21 port 80,443 proto tcp
ufw allow out on tailscale0 from any to 192.168.2.20 port 80,443 proto tcp

echo "NET_IFACE_REPLACE_ME = ${NET_IFACE}"
warn "ufw is disabled. Add the rules to /etc/ufw/before.rules, then run: ufw enable"
