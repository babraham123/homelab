#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@secsvcs CMD

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
  install_postgres)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh postgres
    ;;
  install_lldap)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh lldap
    ;;
  install_authelia)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh authelia
    ;;
  install_traefik)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh traefik
    ;;
  install_victoriametrics)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh victoriametrics
    ;;
  install_victorialogs)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh victorialogs
    ;;
  install_gatus)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh gatus
    ;;
  install_vmalert)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh vmalert
    ;;
  install_alertmanager)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh alertmanager
    ;;
  install_ntfy)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh ntfy
    ;;
  install_grafana)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh grafana
    ;;
  install_vault)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh vault
    ;;
  install_olive_tin)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh olive_tin
    ;;
  install_fluentbit)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh fluentbit
    ;;
  install_all_svcs)
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh postgres
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh lldap
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh authelia
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh traefik
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh victoriametrics
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh victorialogs
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh gatus
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh vmalert
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh alertmanager
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh ntfy
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh grafana
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh vault
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh olive_tin
    sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh fluentbit
    ;;
  install_keys)
    sudo /root/homelab-rendered/src/secsvcs/commands.sh install_keys
    ;;
  install_certs)
    sudo /root/homelab-rendered/src/secsvcs/commands.sh install_certs
    ;;
  install_ssh_ca)
    sudo /root/homelab-rendered/src/debian/commands.sh install_ssh_ca
    ;;
  install_dispatcher)
    sudo /root/homelab-rendered/src/debian/commands.sh install_dispatcher
    ;;
  install_olive_tin_cert)
    sudo /root/homelab-rendered/src/secsvcs/commands.sh install_olive_tin_cert
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
