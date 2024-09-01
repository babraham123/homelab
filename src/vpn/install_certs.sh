#!/usr/bin/env bash
# Moves the certificates into their respective locations. VPN only.
# Usage:
#   src/vpn/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

chmod 640 vpnui.all.pem
mv vpnui.all.pem /etc/haproxy/certs/vpnui.all.pem

rm -rf ./*.pem
