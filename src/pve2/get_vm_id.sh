#!/usr/bin/env bash
# /usr/local/bin/get_vm_id.sh VM_NAME

set -euo pipefail

qm list | grep -i "$1" | sed -r 's/^\s*([0-9]+)\s+.*$/\1/' | head -c -1
