#!/bin/bash
# One node's backup now, outside the weekly run: runs its backup.sh and brings the stage
# into pve1's collection, as the orchestrator's backup_<node> step does. PBS gets it on
# the next weekly upload.
# Usage:
#   src/nodes/pve1/collect_stage.sh NODE [DEST]   # DEST defaults to /root/backups/NODE

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

require_root
[[ $# -ge 1 ]] || die "usage: $0 NODE [DEST]"
stage_collect "$1" "${2:-/root/backups/$1}"
