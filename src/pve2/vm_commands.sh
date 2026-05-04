#!/bin/bash
# Usage:
#   src/pve2/vm_commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/manualadmin

case $1 in
  start_gaming)
    vm_id=$(/usr/local/bin/get_vm_id.sh gaming)
    qm start "$vm_id"
    ;;
  stop_gaming)
    vm_id=$(/usr/local/bin/get_vm_id.sh devtop)
    qm start "$vm_id"
    ;;
  *)
    echo "error: unknown command: $1" >&2
    exit 1
    ;;
esac
