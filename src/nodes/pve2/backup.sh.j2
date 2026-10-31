#!/bin/bash
# pve2 backup: stages the host's and PBS's config under /var/opt/backups for pve1's
# backup_orchestrator to pull, then backs up every VM on this host to PBS through the
# API. Retention is prune.sh, which the orchestrator runs after its own upload.
# Usage:
#   src/nodes/pve2/backup.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

vm_running() { qm status "$1" | grep -qw running; }
backup_vm() { vzdump_to pbs2 --vmid "$1"; }

stage_init
# All of /etc, so no host config is missed. It includes /etc/pve (pmxcfs: storage,
# VM configs, users) and /etc/proxmox-backup, PBS itself: datastore and namespace
# definitions, users, tokens and ACLs, prune/GC jobs, the one thing PBS can't restore
# from PBS.
stage_paths /etc /root/.ssh /var/lib/vz/snippets /usr/local/bin
stage_send

websvcs=$("${rendered}/nodes/pve2/get_vm_id.sh" websvcs)
devtop=$("${rendered}/nodes/pve2/get_vm_id.sh" devtop)
gaming=$("${rendered}/nodes/pve2/get_vm_id.sh" gaming)

# gaming is not backed up: Windows and the games library are reinstalled, not restored,
# and its image would not fit the datastore. devtop and gaming share the GPU: vzdump
# launches a paused QEMU, GPU attached, to read a stopped VM's disks whatever the mode,
# and the hookscript then stops the other VM. So a stopped devtop is imaged with gaming
# off, and gaming comes back after.
backup_vm "$websvcs"
gaming_was_running=0
if ! vm_running "$devtop" && vm_running "$gaming"; then
  gaming_was_running=1
  # The gaming VM can ignore ACPI mid-session; forceStop makes the timeout a hard stop.
  qm shutdown "$gaming" --timeout 180 --forceStop 1
fi
backup_vm "$devtop"
if (( gaming_was_running )); then
  qm start "$gaming"
fi
