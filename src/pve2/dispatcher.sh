#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@pve2 CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_certs_and_keys)
    sudo /root/homelab-rendered/src/pve2/commands.sh install_certs_and_keys
    ;;
  install_vm_watchdog)
    sudo /root/homelab-rendered/src/debian/install_svcs.sh vm_watchdog
    ;;
  start_gaming)
    sudo /root/homelab-rendered/src/pve2/commands.sh start_gaming
    ;;
  stop_gaming)
    sudo /root/homelab-rendered/src/pve2/commands.sh stop_gaming
    ;;
  shutdown)
    sudo /usr/sbin/shutdown -h now
    ;;
  install_ssh_ca)
    sudo /root/homelab-rendered/src/debian/commands.sh install_ssh_ca
    ;;
  install_ca)
    sudo /root/homelab-rendered/src/debian/commands.sh install_ca
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
