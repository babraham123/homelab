#!/bin/bash
# Usage:
#   src/pve2/commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/autoadmin

case $1 in
  start_gaming_vm)
    ping -c1 -W1 {{ gaming.ip }} && exit 0
    vm_id=$(/usr/local/bin/get_vm_id.sh devtop)
    qm shutdown "$vm_id" --timeout 30
    # If the VM is stuck it will be stopped by the hookscript
    vm_id=$(/usr/local/bin/get_vm_id.sh gaming)
    qm start "$vm_id" --timeout 30
    sleep 10
    ;;
  stop_gaming_vm)
    vm_id=$(/usr/local/bin/get_vm_id.sh gaming)
    qm shutdown "$vm_id" --timeout 30
    # If the VM is stuck it will be stopped by the hookscript
    vm_id=$(/usr/local/bin/get_vm_id.sh devtop)
    qm start "$vm_id" --timeout 30
    ;;
  install_certs_and_keys)
    # Moves the certificates into their respective locations and restarts the services.
    # Also configures the PBS cert fingerprint.
    cp pveproxy-ssl.* /etc/pve/nodes/pve2/
    # Ref: https://forum.proxmox.com/threads/proxmox-backup-tailscale-proxmox-backup-proxy-service-wont-boot.153204/
    cp proxy.* /etc/proxmox-backup/

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
