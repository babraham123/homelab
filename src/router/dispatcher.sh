#!/bin/sh
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@router CMD

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin
set -eu

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_certs)
    sudo /root/router-src/commands.sh install_certs
    ;;
  install_dispatcher)
    sudo /root/router-src/commands.sh install_dispatcher
    ;;
  start_pve2)
    sudo /root/router-src/commands.sh start_pve2
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
