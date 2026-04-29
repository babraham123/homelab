#!/usr/bin/env bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@devtop CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

echo "Request received: '${SSH_ORIGINAL_COMMAND}' from ${SSH_CLIENT}"

case "$SSH_ORIGINAL_COMMAND" in
  check_gpu)
    nvidia-smi
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND}'"
    exit 1
    ;;
esac
exit 0
