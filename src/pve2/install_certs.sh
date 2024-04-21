#!/usr/bin/env bash
# src/pve2/install_certs.sh

set -euo pipefail

cd /home/{{ username }}

mv pveproxy-ssl.* /etc/pve/nodes/pve2/
chown root:www-data /etc/pve/nodes/pve2/pveproxy-ssl.pem /etc/pve/nodes/pve2/pveproxy-ssl.key
chmod 640 /etc/pve/nodes/pve2/pveproxy-ssl.pem /etc/pve/nodes/pve2/pveproxy-ssl.key

mv proxy.* /etc/proxmox-backup/
chown root:backup /etc/proxmox-backup/proxy.pem /etc/proxmox-backup/proxy.key
chmod 640 /etc/proxmox-backup/proxy.pem /etc/proxmox-backup/proxy.key

systemctl restart pveproxy.service
systemctl reload proxmox-backup-proxy.service

rm -rf ./*.pem
rm -rf ./*.key
