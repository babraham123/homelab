#!/bin/bash
# vpnsvcs backup: a consistent snapshot of the Headscale database plus the state and
# config that a fresh Debian install can't regenerate, staged under /var/opt/backups
# for pve1's backup_orchestrator to pull. The OS itself is rebuilt from
# docs/guides/vpnsvcs.md; Linode's own backups cover the rest.
# Usage:
#   src/vpnsvcs/backup.sh

set -euo pipefail
# shellcheck source=src/debian/backup_lib.sh
source /root/homelab-rendered/src/debian/backup_lib.sh

command -v sqlite3 > /dev/null || { echo "error: sqlite3 is not installed" >&2; exit 1; }
stage_init

# Headscale's DB is in WAL mode, so copying its files mid-write can capture a torn
# state. .backup snapshots it consistently while headscale keeps serving.
db=/var/lib/headscale/db.sqlite
dir=$(dump_dir headscale)
snapshot="${dir}/db-$(date +%Y-%m-%dT%H%M%S).sqlite"
sqlite3 "$db" ".backup '${snapshot}'"
sqlite3 "$snapshot" 'PRAGMA integrity_check' | grep -qx ok || {
  rm -f "$snapshot"
  echo "error: Headscale DB snapshot failed its integrity check" >&2
  exit 1
}
keep_newest "$dir" 'db-*.sqlite' 1

# The live DB files are excluded in favour of the snapshot. /var/lib/headscale also
# holds the noise and DERP private keys: losing them re-registers every tailnet node.
rsync_excludes+=(--exclude='/var/lib/headscale/db.sqlite*' --exclude='/var/lib/headscale/cache')
stage_paths /var/lib/headscale /etc/headscale /var/lib/tailscale /etc/haproxy \
  /etc/ssh /etc/ufw /etc/opt /etc/systemd/system /etc/letsencrypt /root/.ssh

stage_finish
