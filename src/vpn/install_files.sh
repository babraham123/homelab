#!/usr/bin/env bash
# Usage:
#   src/vpn/install_files.sh TYPE
# type = repo
# Installs the rendered repo source.
# type = certs
# Moves the certificates into their respective locations. VPN only.

set -euo pipefail

cd /home/manualadmin

case $1 in
  repo)
    chown -R root:root homelab-rendered
    mv homelab-rendered /root
    ;;
  certs)
    chown root:root ./*.pem

    chmod 640 vpnui.all.pem
    mv vpnui.all.pem /etc/haproxy/certs/vpnui.all.pem

    rm -rf ./*.pem
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
