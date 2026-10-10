#!/bin/bash
# The backup stage, both ends. Every node's backup.sh rebuilds /var/opt/backups from
# scratch (config trees and volume copies under files/, application dumps under
# dumps/<name>/), streams it as a tar on stdout and deletes it, so no copy of the
# secrets it holds stays on the node. pve1's backup_orchestrator collects each stream
# into /root/backups/<node>/ and sends that to PBS. Nothing here needs to be an archive
# at rest: plain trees dedup better in PBS than tarballs do.
# Usage, from a backup.sh running as root, after src/base/lib.sh:
#   source "${rendered}/base/debian/backup_lib.sh"
#   stage_init                   # empties the stage. From here on stdout is the stream:
#                                # everything else the script prints goes to stderr
#   dump_dir NAME                # prints dumps/NAME, created
#   excludes+=(--exclude=PAT)    # tar patterns, relative to / (or the volume root),
#                                # applied to every stage_* call after
#   stage_paths PATH...          # copies each path into files/, paths as on the live
#                                # system, so files/etc/opt/... restores to /
#   stage_volume VOLUME [NAME]   # copies a Podman volume into files/volumes/NAME
#   stage_send                   # permissions, SHA256SUMS of every file, the tar on
#                                # stdout, then the stage is deleted
#   vzdump_to STORAGE VZDUMP_ARG...  # snapshot-mode vzdump, e.g. pbs2 --all 1 or
#                                    # local --vmid ID; blocks, prints its log, fails
#                                    # unless it ended OK
# and from pve1's backup_orchestrator, after src/base/lib.sh:
#   stage_collect NODE DEST      # runs NODE's backup.sh and brings its stage into DEST
# BACKUP_STAGE overrides the stage root on this machine, e.g. a temp dir to try a run.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

stage=${BACKUP_STAGE:-/var/opt/backups}
files="${stage}/files"
dumps="${stage}/dumps"
excludes=(--exclude='*.tmp' --exclude=lost+found)
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=60)

# Keeps stdout as fd 3 for stage_send and sends everything else to stderr, so what the
# script and its tools print can't corrupt the stream.
stage_init() {
  rm -rf "$stage"
  install -d -m 700 "$stage" "$files" "$dumps"
  exec 3>&1 1>&2
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

# The manifest lets the receiver tell a complete stage from a truncated stream or a file
# that changed under tar. Group and others get nothing: the stage holds secrets files
# and private keys.
stage_send() {
  chmod -R u=rwX,go= "$stage"
  (cd "$stage" && find files dumps -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum > SHA256SUMS)
  echo "Sending $(du -sh "$stage" | cut -f1) from ${stage}"
  tar -C "$stage" -c SHA256SUMS files dumps >&3
  rm -rf "$stage"
}

# Usage: stage_collect NODE DEST. Receives NODE's stream into a private dir next to DEST
# and checks its SHA256SUMS before anything in DEST changes: then files/ is replaced
# and the dumps are added. Only the newest dump of each kind is kept, so a failed
# upload leaves one behind, not a pile.
stage_collect() {
  local node=$1 dest=$2 parent tmp dir
  parent=$(dirname "$dest")
  install -d -m 700 "$parent" "$dest" "${dest}/dumps"
  # A run killed mid-collect leaves its dir behind; the same filesystem makes the mv atomic.
  rm -rf "${parent}"/.incoming.*
  tmp=$(mktemp -d -p "$parent" .incoming.XXXXXX)
  if ! stage_stream "$node" | tar -C "$tmp" -x || ! (cd "$tmp" && sha256sum -c --quiet SHA256SUMS); then
    rm -rf "$tmp"
    die "${node}: stage not received intact"
  fi
  rm -rf "${dest}/files"
  mv "${tmp}/files" "${dest}/files"
  cp -a "${tmp}/dumps/." "${dest}/dumps/"
  rm -rf "$tmp"
  for dir in "${dest}"/dumps/*/; do
    if [[ -d $dir ]]; then
      find "$dir" -maxdepth 1 -type f | sort | head -n -1 | xargs -r rm -f --
    fi
  done
}

# Usage: stage_stream NODE. NODE's backup.sh, run here for this host, otherwise through
# the dispatcher's `backup` command, the one way to that stream: the dispatcher answers
# only pve1's certificate for it. It passes no environment, so the node's stage is the
# default.
stage_stream() {
  if [[ $1 == "$(hostname)" ]]; then
    # shellcheck disable=SC2154 # rendered is set by src/base/lib.sh, sourced first
    "${rendered}/nodes/$1/backup.sh"
  else
    ssh "${ssh_opts[@]}" "autoadmin@$1" backup
  fi
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
vzdump_to() {
  local storage=$1 upid
  shift
  upid=$(pvesh create "/nodes/$(hostname)/vzdump" "$@" --storage "$storage" --mode snapshot \
    --notes-template '{{guestname}}')
  pve_task "$upid"
}
