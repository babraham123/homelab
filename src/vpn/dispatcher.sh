#!/usr/bin/env bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@vpn CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

echo "Request received: '${SSH_ORIGINAL_COMMAND}' from ${SSH_CLIENT}"

case "$SSH_ORIGINAL_COMMAND" in
  install_headscale)
    sudo /root/homelab-rendered/src/vpn/install_svcs.sh headscale
    ;;
  install_tailscaled)
    sudo /root/homelab-rendered/src/vpn/install_svcs.sh tailscaled
    ;;
  install_haproxy)
    sudo /root/homelab-rendered/src/vpn/install_svcs.sh haproxy
    ;;
  install_geoip_generator)
    sudo /root/homelab-rendered/src/vpn/install_svcs.sh geoip_generator
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND}'"
    exit 1
    ;;
esac
exit 0
