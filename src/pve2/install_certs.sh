#!/usr/bin/env bash
# src/pve2/install_certs.sh

set -euo pipefail

cd /home/{{ username }}

chown root:www-data pveproxy-ssl.*
chmod 640 pveproxy-ssl.*
mv pveproxy-ssl.* /etc/pve/nodes/pve2/

chown root:backup proxy.*
chmod 640 proxy.*
mv proxy.* /etc/proxmox-backup/

systemctl restart pveproxy.service
systemctl restart proxmox-backup-proxy.service

rm -rf ./*.pem
rm -rf ./*.key
