#!/bin/bash
# Shared by every node's backup.sh. Each node stages what is worth keeping under
# /var/opt/backups: config trees and volume copies under files/, application dumps
# under dumps/<name>/. pve1's backup_orchestrator mirrors files/ into
# /root/backups/<node>/, moves the dumps there, and sends the collection to PBS; the
# dumps are deleted once that upload succeeds. Nothing here needs to be an archive:
# plain trees dedup better in PBS than tarballs do.
# Usage, from a backup.sh running as root:
#   source /root/homelab-rendered/src/debian/backup_lib.sh
#   stage_init [OWNER]           # OWNER defaults to autoadmin, the user pve1 pulls as
#   dump_dir NAME                # prints dumps/NAME, created; only the newest dump is
#                                # kept there, in case the last pull never came
#   stage_paths PATH...          # mirrors each path into files/ (--relative, --delete)
#   stage_volume VOLUME [NAME]   # mirrors a Podman volume into files/volumes/NAME
#   keep_newest DIR GLOB N       # deletes all but the newest N matches; ISO timestamps
#                                # in the names make sort order chronological
#   stage_finish                 # ownership and permissions of the whole stage
#   pve_task UPID                # waits for a PVE task (pvesh create returns its UPID),
#                                # prints its log, fails unless it ended OK

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

stage=/var/opt/backups
files="${stage}/files"
dumps="${stage}/dumps"
stage_owner=autoadmin

stage_init() {
  stage_owner=${1:-autoadmin}
  command -v rsync > /dev/null || { echo "error: rsync is not installed (apt install rsync)" >&2; exit 1; }
  install -d -m 700 -o "$stage_owner" -g "$stage_owner" "$stage"
  install -d -m 700 "$files" "$dumps"
}

dump_dir() {
  install -d -m 700 "${dumps}/$1"
  echo "${dumps}/$1"
}

stage_paths() {
  local path present=() missing=()
  for path in "$@"; do
    if [[ -e $path ]]; then present+=("$path"); else missing+=("$path"); fi
  done
  if (( ${#missing[@]} )); then
    echo "warning: not staged, missing: ${missing[*]}" >&2
  fi
  # --relative keeps the source path under files/, so files/etc/opt/... restores to /
  # by inspection. --delete drops files that vanished at the source.
  rsync -a --relative --delete --delete-excluded "${rsync_excludes[@]}" "${present[@]}" "${files}/"
}

# Excludes applied to every stage_paths call; nodes append to it before staging.
rsync_excludes=(--exclude='*.tmp' --exclude='lost+found')

stage_volume() {
  local volume=$1 name=${2:-$1} mountpoint
  mountpoint=$(podman volume inspect -f '{{ .Mountpoint }}' "systemd-${volume}")
  install -d -m 700 "${files}/volumes"
  rsync -a --delete "${rsync_excludes[@]}" "${mountpoint}/" "${files}/volumes/${name}/"
}

keep_newest() {
  local dir=$1 glob=$2 n=$3
  find "$dir" -maxdepth 1 -name "$glob" | sort | head -n "-${n}" | xargs -r rm -rf --
}

stage_finish() {
  # One owner for the whole tree so a single rsync as that user reads all of it. Group
  # and others get nothing: the stage holds secrets files and private keys.
  chown -R "${stage_owner}:${stage_owner}" "$stage"
  chmod -R u=rwX,go= "$stage"
  echo "Staged $(du -sh "$stage" | cut -f1) in ${stage}"
}

# vzdump through the API returns at once with a UPID; the task runs on. Polling its
# status is what makes the call block, and the log is where vzdump reports per VM.
pve_task() {
  local upid=$1 node status
  node=$(hostname)
  while status=$(pvesh get "/nodes/${node}/tasks/${upid}/status" --output-format json) &&
        [[ $(jq -r .status <<< "$status") == running ]]; do
    sleep 15
  done
  pvesh get "/nodes/${node}/tasks/${upid}/log" --output-format json | jq -r '.[].t'
  [[ $(jq -r .exitstatus <<< "$status") == OK ]] || {
    echo "error: task ${upid} ended with $(jq -r .exitstatus <<< "$status")" >&2
    return 1
  }
}
