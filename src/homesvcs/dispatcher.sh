#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@homesvcs CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_mdns_repeater)
    sudo /root/homelab-rendered/src/debian/install_svcs.sh mdns_repeater
    ;;
  install_node_exporter)
    sudo /root/homelab-rendered/src/debian/install_svcs.sh node_exporter
    ;;
  install_traefik)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh traefik
    ;;
  install_vmagent)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh vmagent
    ;;
  install_mosquitto)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh mosquitto
    ;;
  install_zigbee2mqtt)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh zigbee2mqtt
    ;;
  install_esphome)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh esphome
    ;;
  install_home_assistant)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh home_assistant
    ;;
  install_fluentbit)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh fluentbit
    ;;
  install_all_svcs)
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh traefik
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh vmagent
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh mosquitto
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh zigbee2mqtt
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh esphome
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh home_assistant
    sudo /root/homelab-rendered/src/homesvcs/install_svcs.sh fluentbit
    ;;
  install_keys)
    sudo /root/homelab-rendered/src/homesvcs/commands.sh install_keys
    ;;
  install_certs)
    sudo /root/homelab-rendered/src/homesvcs/commands.sh install_certs
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
  copy_acme_certs)
    sudo /root/homelab-rendered/src/debian/commands.sh copy_acme_certs
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
