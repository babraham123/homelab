#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@vpnsvcs CMD

# shellcheck source=src/base/lib.sh
source /usr/local/lib/homelab/lib.sh

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_node_exporter)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
    ;;
  install_headscale)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh headscale
    ;;
  install_tailscaled)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh tailscaled
    ;;
  install_haproxy)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh haproxy
    ;;
  install_deadman)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh deadman
    ;;
  install_fluentbit)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh fluentbit
    ;;
  install_vmagent)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh vmagent
    ;;
  install_geoip_generator)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh geoip_generator
    ;;
  backup)
    sudo /root/homelab-rendered/src/nodes/vpnsvcs/backup.sh
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
