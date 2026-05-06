#!/bin/bash
# Usage:
#   src/pve2/commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/autoadmin

case $1 in
  start_gaming)
    vm_id=$(/usr/local/bin/get_vm_id.sh gaming)
    qm start "$vm_id"
    ;;
  stop_gaming)
    # This is intentional. Starting devtop will stop gaming via the hookscript.
    vm_id=$(/usr/local/bin/get_vm_id.sh devtop)
    qm start "$vm_id"
    ;;
  install_certs_and_keys)
    # Moves the certificates into their respective locations and restarts the services.
    # Also configures the PBS cert fingerprint.
    mv pveproxy-ssl.* /etc/pve/nodes/pve2/
    chown root:www-data /etc/pve/nodes/pve2/pveproxy-ssl.pem /etc/pve/nodes/pve2/pveproxy-ssl.key
    chmod 640 /etc/pve/nodes/pve2/pveproxy-ssl.pem /etc/pve/nodes/pve2/pveproxy-ssl.key

    # Ref: https://forum.proxmox.com/threads/proxmox-backup-tailscale-proxmox-backup-proxy-service-wont-boot.153204/
    mv proxy.* /etc/proxmox-backup/
    chown backup:backup /etc/proxmox-backup/proxy.pem /etc/proxmox-backup/proxy.key
    chmod 640 /etc/proxmox-backup/proxy.pem /etc/proxmox-backup/proxy.key

    systemctl restart pveproxy.service
    systemctl reload proxmox-backup-proxy.service
    rm -rf ./*.pem
    rm -rf ./*.key

    # Update PBS fingerprint for PVE2
    # Ref: https://pbs.proxmox.com/docs/pve-integration.html
    fingerprint=$(proxmox-backup-manager cert info | grep "Fingerprint" | sed -r 's/Fingerprint\s+\(sha256\):\s+([a-f0-9:]+)/\1/')
    pvesm set pbs2 --fingerprint "$fingerprint"

    # Print out the fingerprint for PVE1
    echo "$fingerprint"
    ;;
  *)
    echo "error: unknown command: $1" >&2
    exit 1
    ;;
esac
