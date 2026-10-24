#!/bin/bash
# Runs a snapraid sync or scrub, then records the result for node_exporter. Driven by
# snapraid-sync.timer (daily) and snapraid-scrub.timer (weekly). The array is media only;
# parity is its only protection, so a failed sync is worth an alert
# (src/services/vmalert/configs/backups.yml).
# Usage:
#   /usr/local/bin/snapraid_run.sh sync|scrub

# shellcheck source=src/base/lib.sh
source /usr/local/lib/homelab/lib.sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

job=${1:-}
textfile=/var/lib/node_exporter/textfile_collector
mounts=(/mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/parity)
(( ${#mounts[@]} )) || die "no disks in websvcs.media.disks (vars.yml)"

# Usage: write_prom FILE LINES...; atomic, node_exporter only reads *.prom
write_prom() {
  local file="${textfile}/$1"
  shift
  mkdir -p "$textfile"
  printf '%s\n' "$@" > "${file}.tmp"
  chmod 644 "${file}.tmp"
  mv "${file}.tmp" "$file"
}

case $job in
  sync)
    # Every mount must be present, or snapraid would sync a missing disk as deleted.
    for mount in "${mounts[@]}"; do
      mountpoint -q "$mount" || die "${mount} is not mounted"
    done
    # diff exits 2 when there are changes, 0 when there are none, 1 on error.
    set +e
    diff=$(snapraid diff 2>&1)
    rc=$?
    set -e
    (( rc == 0 || rc == 2 )) || die "$diff"
    # A bad rm or ransomware would otherwise be written into parity.
    threshold=200
    removed=$(awk '/removed$/ {print $1}' <<< "$diff")
    if (( removed > threshold )); then
      die "${removed} files removed since the last sync, over the threshold of ${threshold}." \
        "If that is intended: snapraid sync --force-empty, or run this with the threshold raised."
    fi
    snapraid sync
    ;;
  scrub)
    # 8% of the oldest blocks each week checks every block about once a quarter.
    snapraid scrub -p 8 -o 10
    ;;
  *)
    die "usage: $0 sync|scrub"
    ;;
esac

write_prom "homelab_snapraid_${job}.prom" \
  '# HELP homelab_snapraid_last_success_timestamp_seconds Unix time of the last successful snapraid job.' \
  '# TYPE homelab_snapraid_last_success_timestamp_seconds gauge' \
  "homelab_snapraid_last_success_timestamp_seconds{job=\"${job}\"} $(date +%s)"
