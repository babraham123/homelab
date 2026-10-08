#!/bin/bash
# Shared by every node's backup.sh. Each run rebuilds /var/opt/backups from scratch:
# config trees and volume copies under files/, application dumps under dumps/<name>/.
# pve1's backup_orchestrator copies files/ into /root/backups/<node>/, moves the dumps
# there, and sends the collection to PBS. Nothing here needs to be an archive: plain
# trees dedup better in PBS than tarballs do.
# Usage, from a backup.sh running as root:
#   source /root/homelab-rendered/src/debian/backup_lib.sh
#   stage_init [OWNER]           # empties the stage; OWNER defaults to autoadmin, the
#                                # user pve1 pulls as
#   dump_dir NAME                # prints dumps/NAME, created
#   excludes+=(--exclude=PAT)    # tar patterns, relative to / (or the volume root),
#                                # applied to every stage_* call after
#   stage_paths PATH...          # copies each path into files/, paths as on the live
#                                # system, so files/etc/opt/... restores to /
#   stage_volume VOLUME [NAME]   # copies a Podman volume into files/volumes/NAME
#   stage_finish                 # ownership and permissions of the whole stage
#   pve_task UPID                # waits for a PVE task (pvesh create returns its UPID),
#                                # prints its log, fails unless it ended OK

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

stage=/var/opt/backups
files="${stage}/files"
dumps="${stage}/dumps"
stage_owner=autoadmin
excludes=(--exclude='*.tmp' --exclude=lost+found)

stage_init() {
  stage_owner=${1:-autoadmin}
  rm -rf "$stage"
  install -d -m 700 "$stage" "$files" "$dumps"
}

dump_dir() {
  install -d -m 700 "${dumps}/$1"
  echo "${dumps}/$1"
}

# Usage: copy SRC DEST MEMBER... (MEMBERs relative to SRC). tar exits 1 for "file
# changed as we read it", expected for SQLite under a live process; 2 is a real error.
copy() {
  local src=$1 dest=$2
  shift 2
  install -d -m 700 "$dest"
  tar -C "$src" -c "${excludes[@]}" "$@" | tar -C "$dest" -x ||
    (( PIPESTATUS[0] < 2 && PIPESTATUS[1] == 0 ))
}

stage_paths() {
  local path present=()
  for path in "$@"; do
    if [[ -e $path ]]; then present+=("${path#/}"); else echo "warning: not staged, missing: $path" >&2; fi
  done
  copy / "$files" "${present[@]}"
}

stage_volume() {
  local volume=$1 name=${2:-$1}
  copy "$(podman volume inspect -f '{{ .Mountpoint }}' "systemd-${volume}")" "${files}/volumes/${name}" .
}

stage_finish() {
  # One owner for the whole tree so sftp as that user reads all of it. Group and
  # others get nothing: the stage holds secrets files and private keys.
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
