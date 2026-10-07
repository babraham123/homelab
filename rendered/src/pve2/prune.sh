#!/bin/bash
# PBS retention: creates or updates one prune job per namespace, runs them, then runs
# garbage collection. The orchestrator calls this after its upload step, so the
# newest snapshots are counted, and only then, since PBS is only up during the run.
# Retention lives here, not in the PBS UI. One job per namespace because prune jobs
# can't tell images from host backups otherwise.
# Usage:
#   src/pve2/prune.sh

set -euo pipefail

store=backup1

# PBS tasks (prune, GC) return a UPID and run on.
pbs_task() {
  local upid=$1 task
  until task=$(proxmox-backup-manager task list --all --limit 200 --output-format json | \
      jq -e --arg u "$upid" '.[] | select(.upid == $u and .endtime != null)'); do
    sleep 15
  done
  proxmox-backup-manager task log "$upid" || true
  [[ $(jq -r .status <<< "$task") == OK ]] || {
    echo "error: PBS task ${upid} ended with $(jq -r .status <<< "$task")" >&2
    return 1
  }
}

# Usage: prune_job NAME NAMESPACE KEEP_OPTS...
prune_job() {
  local job=$1 ns=$2
  shift 2
  if proxmox-backup-manager prune-job show "$job" &> /dev/null; then
    proxmox-backup-manager prune-job update "$job" "$@"
  else
    proxmox-backup-manager prune-job create "$job" --store "$store" --ns "$ns" --max-depth 0 \
      --schedule daily "$@"
  fi
  pbs_task "$(proxmox-backup-manager prune-job run "$job" --output-format json | jq -r .)"
}

# Images (pve1, pve2 namespaces; vpnsvcs' host backup sits with pve1's images) are
# kept short; the files collection longer.
prune_job images-pve1 pve1 --keep-last 1 --keep-weekly 2 --keep-monthly 2
prune_job images-pve2 pve2 --keep-last 1 --keep-weekly 2 --keep-monthly 2
prune_job files files --keep-last 1 --keep-weekly 3 --keep-monthly 6
pbs_task "$(proxmox-backup-manager garbage-collection start "$store" --output-format json | jq -r .)"
