#!/usr/bin/env bash
# Moves the certificates into their respective locations and restarts the services.
# Also configures the PBS cert fingerprint. PVE2 only.
# Usage:
#   src/pve2/install_certs.sh

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

# Update PBS fingerprint for PVE2
# Ref: https://pbs.proxmox.com/docs/pve-integration.html
fingerprint=$(proxmox-backup-manager cert info | grep "Fingerprint" | sed -r 's/Fingerprint\s+\(sha256\):\s+([a-f0-9:]+)/\1/')
pvesm set pbs2 --fingerprint "$fingerprint"

# Print out the certificate info for PVE1
proxmox-backup-manager cert info
