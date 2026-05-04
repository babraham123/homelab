#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@pve1 CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

echo "Request received: '${SSH_ORIGINAL_COMMAND}' from ${SSH_CLIENT}"

case "$SSH_ORIGINAL_COMMAND" in
  install_cert_notifier)
    sudo /root/homelab-rendered/src/pve1/install_svcs.sh cert_notifier
    ;;
  install_vm_watchdog)
    sudo /root/homelab-rendered/src/debian/install_svcs.sh vm_watchdog
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
