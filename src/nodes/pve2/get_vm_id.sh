#!/bin/bash
# Prints out the proxmox VM ID if given it's name.
# Usage:
#   src/pve2/get_vm_id.sh VM_NAME
# Called in place from /root/homelab-rendered, so a deploy updates it.

set -euo pipefail

qm list | grep -i "$1" | sed -r 's/^\s*([0-9]+)\s+.*$/\1/' | head -c -1
