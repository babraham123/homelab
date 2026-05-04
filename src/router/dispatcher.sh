#!/bin/sh
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@router CMD

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin
set -eu

echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_certs)
    sudo /usr/local/bin/commands.sh install_certs
    ;;
  start_pve2)
    sudo /usr/local/bin/commands.sh start_pve2
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
