#!/bin/bash
# Weekly backup run. Wakes pve2 (PBS lives there), runs backup.sh on every node, pulls
# each node's stage into /root/backups/<node>/, sends /root/backups to PBS as host
# backups, has pve2 prune and garbage-collect PBS, records per-step success metrics,
# then powers pve2 back off if it was off to begin with. Posts a one-line ntfy summary
# at the end.
# Usage:
#   /usr/local/bin/backup_orchestrator.sh
# Adding a node: give it a backup.sh and a `backup` dispatcher command, then list it in
# NODES. Adding another step: write a step_<name> function and list it in STEPS.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

storage=pbs2
backups=/root/backups
metrics=/var/lib/node_exporter/textfile_collector/homelab_backup.prom
ssh=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=60)
is_reachable=/root/homelab-rendered/src/debian/is_reachable.sh
keyfile=/root/secrets/pbs_client.key

# In step order. The VMs first, so their dumps are on the VM disks before the hosts'
# backup.sh images them. prune comes after upload so this week's snapshots count.
NODES=(secsvcs homesvcs websvcs vpnsvcs pve1 pve2)
# wake_pve2 and sleep_pve2 bracket these.
STEPS=()
for node in "${NODES[@]}"; do STEPS+=("backup_${node}"); done
STEPS+=(upload prune)

step_wake_pve2() {
  "${ssh[@]}" autoadmin@router start_pve2
  wait_for 600 "pbs2 unreachable" "$is_reachable" pbs2
  wait_for 300 "PBS storage $storage inactive" storage_active
}

# Usage: pull NODE. Runs the node's backup.sh and brings its stage here: files/ is
# mirrored, dumps/ is moved (the node keeps nothing once they are here). Only the
# newest dump of each kind is kept, so a failed upload leaves one behind, not a pile.
# The stage is owned by autoadmin, the user the dispatcher key logs in as, so rsync
# reads all of it over the same sftp channel scp uses.
pull() {
  local node=$1 src="/var/opt/backups" dir dest
  dest="${backups}/${node}"
  install -d -m 700 "$dest" "${dest}/dumps"
  if [[ $node == pve1 ]]; then
    /root/homelab-rendered/src/pve1/backup.sh
    rsync -a --delete "${src}/files/" "${dest}/files/"
    rsync -a --remove-source-files "${src}/dumps/" "${dest}/dumps/"
  else
    "${ssh[@]}" "autoadmin@${node}" backup
    src="autoadmin@${node}:/var/opt/backups"
    rsync -a --delete -e "${ssh[*]}" "${src}/files/" "${dest}/files/"
    rsync -a --remove-source-files -e "${ssh[*]}" "${src}/dumps/" "${dest}/dumps/"
  fi
  for dir in "${dest}"/dumps/*/; do
    if [[ -d $dir ]]; then
      find "$dir" -maxdepth 1 -type f | sort | head -n -1 | xargs -r rm -f --
    fi
  done
}
for node in "${NODES[@]}"; do
  eval "step_backup_${node}() { pull ${node}; }"
done

# Host backups of the collection, encrypted on this side with the client key, so PBS,
# its disk and any offsite copy only ever hold ciphertext; losing the key loses the
# backups, so it is in the escrow set (docs/guides/pve1_recovery.md). The vpnsvcs
# stage is its own group next to pve1's VM images, since it stands in for the VPS's
# image and takes that retention; everything else goes to the `files` namespace.
# Dumps are deleted once both uploads succeed: PBS holds them from here on.
step_upload() {
  [[ -f $keyfile ]] || { echo "error: ${keyfile} missing" >&2; return 1; }
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

step_sleep_pve2() {
  # The connection can drop as the host goes down, so the ping check is the real result.
  "${ssh[@]}" autoadmin@pve2 shutdown || true
  wait_for 300 "pve2 still up" is_down pve2
}

storage_active() { pvesm status --storage "$storage" | grep -qw active; }
is_down() { ! "$is_reachable" "$1"; }

# Usage: wait_for TIMEOUT_S ERROR_MSG CMD...
wait_for() {
  local timeout=$1 msg=$2 t=0
  shift 2
  until "$@" &>/dev/null; do
    (( t += 10 ))
    if (( t >= timeout )); then
      echo "error: ${msg} after ${timeout}s" >&2
      return 1
    fi
    sleep 10
  done
}

# Usage: secret NAME. Reads pve1's own secrets file; pve1 holds every host's SOPS file.
secret() {
  SOPS_AGE_KEY_FILE=/root/secrets/age.txt sops -d /root/secrets/pve1.yaml | yq ".$1"
}

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
    echo "error: step $1 failed (exit $rc)" >&2
  fi
}

# Keeps the previous timestamp of failed jobs, so staleness alerts fire per job. Jobs
# no longer in STEPS are dropped, or a renamed step would alert as stale forever.
write_metrics() {
  local name='homelab_backup_last_success_timestamp_seconds' job value
  declare -A previous=() last=()
  if [[ -f $metrics ]]; then
    while read -r job value; do
      [[ $job =~ job=\"([^\"]+)\" ]] && previous[${BASH_REMATCH[1]}]=$value
    done < <(grep "^${name}{" "$metrics")
  fi
  for job in "${STEPS[@]}"; do
    [[ -v previous[$job] ]] && last[$job]=${previous[$job]}
    [[ -v done_at[$job] ]] && last[$job]=${done_at[$job]}
  done

  mkdir -p "$(dirname "$metrics")"
  {
    echo "# HELP ${name} Unix time of the last successful backup_orchestrator step."
    echo "# TYPE ${name} gauge"
    for job in "${!last[@]}"; do
      echo "${name}{job=\"${job}\"} ${last[$job]}"
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
  token=$(SOPS_AGE_KEY_FILE=/root/secrets/age.txt sops -d /root/secrets/secsvcs.yaml | yq '.ntfy_alert_token')
  curl -fsS -o /dev/null \
    -H "Authorization: Bearer $token" \
    -H "X-Title: $1" \
    -H "X-Priority: $3" \
    -H "X-Tags: floppy_disk" \
    -d "$2" "https://push.janedoe.com/alert" \
    || echo "warning: ntfy post failed" >&2
}

started=$(date +%s)
pve2_was_on=0
"$is_reachable" pve2 &>/dev/null && pve2_was_on=1
echo "pve2 initially $( (( pve2_was_on )) && echo on || echo off )"

run wake_pve2
if [[ -z "${failed[*]}" ]]; then
  for step in "${STEPS[@]}"; do
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
