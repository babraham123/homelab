#!/bin/bash
# Prints out the proxmox VM ID if given it's name.
# Usage:
#   src/nodes/pve2/get_vm_id.sh VM_NAME
# Called in place from /root/homelab-rendered, so a deploy updates it.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

qm list | grep -i "$1" | sed -r 's/^\s*([0-9]+)\s+.*$/\1/' | head -c -1
