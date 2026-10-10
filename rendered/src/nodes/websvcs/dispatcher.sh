#!/bin/bash
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@websvcs CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

# Modern scp (OpenSSH 9+) uses SFTP protocol by default
if [[ "${SSH_ORIGINAL_COMMAND:-}" == "/usr/lib/openssh/sftp-server" ]]; then
  exec /usr/lib/openssh/sftp-server
fi
echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}"

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_mdns_repeater)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
    ;;
  install_node_exporter)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
    ;;
  install_traefik)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh traefik
    ;;
  install_vmagent)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh vmagent
    ;;
  install_nginx)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh nginx
    ;;
  install_homepage)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh homepage
    ;;
  install_isso)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh isso
    ;;
  install_guacamole)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacamole
    ;;
  install_guacd)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacd
    ;;
  install_fluentbit)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh fluentbit
    ;;
  install_snapraid)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh snapraid
    ;;
  install_all_svcs)
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh traefik
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh vmagent
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh nginx
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh homepage
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh isso
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacamole
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacd
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh fluentbit
    sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh snapraid
    ;;
  install_keys)
    sudo /root/homelab-rendered/src/nodes/websvcs/commands.sh install_keys
    ;;
  install_certs)
    sudo /root/homelab-rendered/src/nodes/websvcs/commands.sh install_certs
    ;;
  backup)
    sudo /root/homelab-rendered/src/nodes/websvcs/backup.sh
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
  copy_acme_certs)
    sudo /root/homelab-rendered/src/base/debian/commands.sh copy_acme_certs
    ;;
  *)
    echo "Unauthorized command: '${SSH_ORIGINAL_COMMAND:-}'"
    exit 1
    ;;
esac
echo "Completed command"
exit 0
