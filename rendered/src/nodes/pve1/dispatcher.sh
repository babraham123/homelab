#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@pve1 CMD

# shellcheck source=src/base/lib.sh
source /usr/local/lib/homelab/lib.sh

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_vm_watchdog)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh vm_watchdog
    ;;
  install_cert_notifier)
    sudo /root/homelab-rendered/src/nodes/pve1/install_svcs.sh cert_notifier
    ;;
  install_backup_orchestrator)
    sudo /root/homelab-rendered/src/nodes/pve1/install_svcs.sh backup_orchestrator
    ;;
  archive_repo)
    sudo /root/homelab-rendered/src/nodes/pve1/commands.sh archive_repo
    ;;
  install_ssh_ca)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
    ;;
  install_dispatcher)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
    ;;
  install_ca)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
