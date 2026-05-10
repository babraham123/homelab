#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@devtop CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  check_gpu)
    sudo /usr/bin/systemctl status nvidia-persistenced --no-pager
    nvidia-smi
    ;;
  install_ssh_ca)
    sudo /root/homelab-rendered/src/debian/commands.sh install_ssh_ca
    ;;
  install_dispatcher)
    sudo /root/homelab-rendered/src/debian/commands.sh install_dispatcher
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
