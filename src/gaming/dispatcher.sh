#!/usr/bin/env bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@gaming CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

echo "Request received: '${SSH_ORIGINAL_COMMAND}' from ${SSH_CLIENT}"

case "$SSH_ORIGINAL_COMMAND" in
  remote_play)
    sudo /root/homelab-rendered/src/gaming/enable_mode.sh remote_play
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND}'"
    exit 1
    ;;
esac
exit 0
