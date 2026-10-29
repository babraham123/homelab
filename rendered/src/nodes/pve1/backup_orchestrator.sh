#!/bin/bash
# Weekly backup run. Dumps the router VM to pve1's own disk, wakes pve2 (PBS lives
# there), runs backup.sh on every node and receives the stage each streams back into
# /root/backups/<node>/ (backup_lib's stage_collect; src/nodes/pve1/collect_stage.sh
# does one node outside the weekly run), sends /root/backups to PBS as host backups,
# has pve2 prune and garbage-collect PBS, installs the renewed ACME certs on the hosts
# (acme_transfer.sh), records per-step success metrics, then powers pve2 back off if it
# was off to begin with. Posts a one-line ntfy summary at the end.
# --skip-next makes the next timer-started run do nothing but clear the skip; a run
# started by hand (pve1's backup_now) still runs.
# Usage:
#   src/nodes/pve1/backup_orchestrator.sh [--skip-next]
# Adding a node: give it a backup.sh and a `backup` dispatcher command, which puts it
# in NODES. Adding another step: write a step_<name> function and list it in
# LOCAL_STEPS if it doesn't need pve2, else PBS_STEPS.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"
# shellcheck source=src/nodes/pve1/secrets_lib.sh
source "${rendered}/nodes/pve1/secrets_lib.sh"

storage=pbs2
backups=/root/backups
metrics=/var/lib/node_exporter/textfile_collector/homelab_backup.prom
skip_flag=/var/lib/backup_orchestrator/skip_next
# backup_lib's ssh_opts, so these calls and the stage transport behave alike.
ssh=(ssh "${ssh_opts[@]}")
keyfile=/root/secrets/pbs_client.key

# In step order. The VMs first, so their dumps are on the VM disks before the hosts'
# backup.sh images them; pve1 runs its own backup.sh, so it has no `backup` command.
# prune comes after upload so this week's snapshots count; acme_transfer comes last, as
# it reloads PBS's proxy and resets pve1's PBS fingerprint.
NODES=(homesvcs secsvcs vpnsvcs websvcs pve1 pve2)
# Run before wake_pve2, and whether or not it succeeds.
LOCAL_STEPS=(router_local)
# wake_pve2 and sleep_pve2 bracket these.
PBS_STEPS=()
for node in "${NODES[@]}"; do PBS_STEPS+=("backup_${node}"); done
PBS_STEPS+=(upload prune acme_transfer)
STEPS=("${LOCAL_STEPS[@]}" "${PBS_STEPS[@]}")

# The router is the network: with it broken, pve2 can't be woken and PBS can't be
# reached, so its images are also kept where pve1 restores them alone, with PBS's
# image retention; vzdump prunes once the new one is written.
step_router_local() {
  local vmid
  vmid=$(qm list | awk '$2 == "router" { print $1 }')
  [[ -n $vmid ]] || die "no router VM"
  vzdump_to local --vmid "$vmid" --compress zstd --prune-backups "$image_retention"
}

step_wake_pve2() {
  "${ssh[@]}" autoadmin@router start_pve2
  wait_reachable pbs2 600
  wait_for 300 "PBS storage $storage inactive" storage_active
}

for node in "${NODES[@]}"; do
  eval "step_backup_${node}() { stage_collect ${node} ${backups}/${node}; }"
done

# Host backups of the collection, encrypted on this side with the client key, so PBS,
# its disk and any offsite copy only ever hold ciphertext; losing the key loses the
# backups, so it is in the escrow set (docs/guides/pve1_recovery.md). The vpnsvcs
# stage is its own group next to pve1's VM images, since it stands in for the VPS's
# image and takes that retention; everything else goes to the `files` namespace.
# Dumps are deleted once both uploads succeed: PBS holds them from here on.
step_upload() {
  [[ -f $keyfile ]] || die "${keyfile} missing"
  export PBS_REPOSITORY='pve1@pbs!backup@pbs2.janedoe.com:backup1'
  PBS_PASSWORD=$(secret pbs2_backup_token)
  export PBS_PASSWORD
  proxmox-backup-client backup "vpnsvcs.pxar:${backups}/vpnsvcs" --ns pve1 --backup-id vpnsvcs \
    --keyfile "$keyfile"
  proxmox-backup-client backup "backups.pxar:${backups}" --ns files --backup-id pve1 \
    --keyfile "$keyfile" --exclude /vpnsvcs --skip-lost-and-found true
  find "$backups" -path '*/dumps/*' -type f -delete
}

# Retention and GC run on pve2, where proxmox-backup-manager is.
step_prune() {
  "${ssh[@]}" autoadmin@pve2 prune
}

# Traefik renews 30 days before expiry, so weekly keeps the hosts well inside a cert's
# life; it needs pve2 up, which this run provides.
step_acme_transfer() {
  "${rendered}/nodes/pve1/certificates/acme_transfer.sh"
}

step_sleep_pve2() {
  # The connection can drop as the host goes down, so the ping check is the real result.
  "${ssh[@]}" autoadmin@pve2 shutdown || true
  wait_for 300 "pve2 still up" is_down pve2
}

storage_active() { pvesm status --storage "$storage" | grep -qw active; }
is_down() { ! is_reachable "$1"; }

# Usage: secret NAME; one of pve1's own secrets
secret() { secret_get pve1 "$1"; }

ok=()
failed=()
declare -A done_at=()

# Runs step_$1 and records the outcome. The subshell re-enables errexit: bash ignores
# `set -e` inside anything called from an if/&&/|| condition.
run() {
  echo "==> $1"
  set +e
  ( set -e; "step_$1" )
  local rc=$?
  set -e
  if (( rc == 0 )); then
    ok+=("$1")
    done_at[$1]=$(date +%s)
  else
    failed+=("$1")
    log "error: step $1 failed (exit $rc)" >&2
  fi
}

# Keeps the previous timestamp of failed steps, so staleness alerts fire per step. Steps
# no longer in STEPS are dropped, or a renamed step would alert as stale forever.
write_metrics() {
  local name='homelab_backup_last_success_timestamp_seconds' step value
  declare -A previous=() last=()
  if [[ -f $metrics ]]; then
    while read -r step value; do
      [[ $step =~ step=\"([^\"]+)\" ]] && previous[${BASH_REMATCH[1]}]=$value
    done < <(grep "^${name}{" "$metrics")
  fi
  for step in "${STEPS[@]}"; do
    [[ -v previous[$step] ]] && last[$step]=${previous[$step]}
    [[ -v done_at[$step] ]] && last[$step]=${done_at[$step]}
  done

  mkdir -p "$(dirname "$metrics")"
  {
    echo "# HELP ${name} Unix time of the last successful backup_orchestrator step."
    echo "# TYPE ${name} gauge"
    for step in "${!last[@]}"; do
      echo "${name}{step=\"${step}\"} ${last[$step]}"
    done
  } > "${metrics}.tmp"
  chmod 644 "${metrics}.tmp"
  # node_exporter only reads *.prom, and the rename is atomic.
  mv "${metrics}.tmp" "$metrics"
}

# Usage: notify TITLE MESSAGE PRIORITY
notify() {
  local token
  # The alert token is a secsvcs secret; pve1 holds every host's secrets file.
  token=$(secret_get secsvcs ntfy_alert_token)
  curl -fsS -o /dev/null \
    -H "Authorization: Bearer $token" \
    -H "X-Title: $1" \
    -H "X-Priority: $3" \
    -H "X-Tags: floppy_disk" \
    -d "$2" "https://push.janedoe.com/alert" \
    || warn "ntfy post failed"
}

if [[ ${1:-} == --skip-next ]]; then
  install -d -m 700 "$(dirname "$skip_flag")"
  touch "$skip_flag"
  echo "Skipping the run due $(systemctl show -P NextElapseUSecRealtime backup_orchestrator.timer)"
  exit 0
fi
# systemd sets TRIGGER_UNIT only when the timer started the service. Skipping writes
# no metrics, so BackupStale's threshold leaves room for one skipped week.
if [[ -f $skip_flag && ${TRIGGER_UNIT:-} == backup_orchestrator.timer ]]; then
  rm -f "$skip_flag"
  notify "Backups skipped" "skip_next_backup was set; the next run is next week" 2
  exit 0
fi

started=$(date +%s)
pve2_was_on=0
is_reachable pve2 && pve2_was_on=1
echo "pve2 initially $( (( pve2_was_on )) && echo on || echo off )"

for step in "${LOCAL_STEPS[@]}"; do
  run "$step"
done
run wake_pve2
if [[ ${done_at[wake_pve2]+set} ]]; then
  for step in "${PBS_STEPS[@]}"; do
    run "$step"
  done
fi
write_metrics || failed+=(write_metrics)
if (( ! pve2_was_on )); then
  run sleep_pve2
fi

minutes=$(( ($(date +%s) - started) / 60 ))
if [[ -z "${failed[*]}" ]]; then
  notify "Backups OK" "${ok[*]} (${minutes} min)" 2
  exit 0
fi
notify "Backups failed" "failed: ${failed[*]}; ok: ${ok[*]:-none} (${minutes} min)" 4
exit 1
