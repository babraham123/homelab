#!/bin/bash
# The backup stage, both ends. Every node's backup.sh rebuilds /var/opt/backups from
# scratch: config trees and volume copies under files/, application dumps under
# dumps/<name>/. pve1's backup_orchestrator collects each stage into
# /root/backups/<node>/ and sends that to PBS. Nothing here needs to be an archive:
# plain trees dedup better in PBS than tarballs do.
# Usage, from a backup.sh running as root, after src/base/lib.sh:
#   source "${rendered}/base/debian/backup_lib.sh"
#   stage_init [OWNER]           # empties the stage; OWNER defaults to autoadmin, the
#                                # user pve1 pulls as
#   dump_dir NAME                # prints dumps/NAME, created
#   excludes+=(--exclude=PAT)    # tar patterns, relative to / (or the volume root),
#                                # applied to every stage_* call after
#   stage_paths PATH...          # copies each path into files/, paths as on the live
#                                # system, so files/etc/opt/... restores to /
#   stage_volume VOLUME [NAME]   # copies a Podman volume into files/volumes/NAME
#   stage_finish                 # ownership and permissions of the whole stage
#   vzdump_to_pbs VZDUMP_ARG...  # snapshot-mode vzdump to PBS, e.g. --all 1 or --vmid ID;
#                                # blocks, prints its log, fails unless it ended OK
# and from pve1's backup_orchestrator, after src/base/lib.sh:
#   stage_collect NODE DEST      # runs NODE's backup.sh and brings its stage into DEST
# BACKUP_STAGE overrides the stage root on this machine, e.g. a temp dir to try a run.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

stage_default=/var/opt/backups
stage=${BACKUP_STAGE:-$stage_default}
files="${stage}/files"
dumps="${stage}/dumps"
stage_owner=autoadmin
excludes=(--exclude='*.tmp' --exclude=lost+found)
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=60)

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
    if [[ -e $path ]]; then present+=("${path#/}"); else warn "not staged, missing: $path"; fi
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

# Usage: stage_collect NODE DEST. files/ in DEST is replaced, dumps/ is moved (the node
# keeps none once they are in DEST). Only the newest dump of each kind is kept, so a
# failed upload leaves one behind, not a pile.
stage_collect() {
  local node=$1 dest=$2 dir
  rm -rf "${dest}/files"
  install -d -m 700 "$dest" "${dest}/dumps"
  if [[ $node == "$(hostname)" ]]; then
    # shellcheck disable=SC2154 # rendered is set by src/base/lib.sh, sourced first
    "${rendered}/nodes/${node}/backup.sh"
    cp -a "${stage}/files" "${dest}/files"
    cp -a "${stage}/dumps/." "${dest}/dumps/"
    find "${stage}/dumps" -type f -delete
  else
    stage_fetch "$node" "$dest"
  fi
  for dir in "${dest}"/dumps/*/; do
    if [[ -d $dir ]]; then
      find "$dir" -maxdepth 1 -type f | sort | head -n -1 | xargs -r rm -f --
    fi
  done
}

# Usage: stage_fetch NODE DEST. The transport for another node: runs its backup.sh
# through the dispatcher, copies files/ and dumps/ into DEST, then deletes the node's
# dumps. sftp is the one transfer the dispatcher passes through, and the stage is owned
# by autoadmin so sftp reads all of it. Symlinks are not copied: sftp skips them with a
# warning. The dispatcher passes no environment, so the node's stage is the default.
stage_fetch() {
  local node=$1 dest=$2 src=$stage_default
  ssh "${ssh_opts[@]}" "autoadmin@${node}" backup
  sftp -q -b - "${ssh_opts[@]}" "autoadmin@${node}" <<EOF
get -pr ${src}/files ${dest}
get -pr ${src}/dumps ${dest}
-rm ${src}/dumps/*/*
EOF
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
  [[ $(jq -r .exitstatus <<< "$status") == OK ]] ||
    die "task ${upid} ended with $(jq -r .exitstatus <<< "$status")"
}

# Snapshot mode keeps the VMs running; PBS stores only the chunks that changed since
# the last run. The notes template names each backup after its guest in the PBS UI.
vzdump_to_pbs() {
  local upid
  upid=$(pvesh create "/nodes/$(hostname)/vzdump" "$@" --storage pbs2 --mode snapshot \
    --notes-template '{{guestname}}')
  pve_task "$upid"
}
