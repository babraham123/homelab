#!/usr/bin/env bash
# Usage:
#   src/pve2/install_files.sh TYPE
# type = ssh_ca
# Moves SSH public keys into their respective locations and restarts sshd.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/manualadmin

case $1 in
  ssh_ca)
    chown root:root ca_ssh_key.pub
    mv ca_ssh_key.pub /etc/ssh

    chown root:root ssh_host_key_cert.pub
    mv ssh_host_key_cert.pub /etc/ssh

    chown root:root known_hosts
    mv known_hosts /etc/ssh/ssh_known_hosts

    systemctl restart sshd
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
