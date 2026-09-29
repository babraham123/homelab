#!/bin/bash
# Full backup of the VPS. It isn't a Proxmox VM, so no vzdump covers it; this archive
# of the whole root filesystem is its backup. Restore steps are in docs/guides/vpnsvcs.md.
# Usage:
#   src/vpnsvcs/backup_full.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

for bin in sqlite3 zstd; do
  command -v "$bin" > /dev/null || { echo "error: $bin is not installed" >&2; exit 1; }
done
# autoadmin owns the directory so pve1 can scp archives off the box; that key can
# already trigger this command, so it gains nothing new.
# TODO: the archive is plaintext, so the autoadmin key (held by pve1 and OliveTin)
# reads the whole root fs: /etc/shadow, the Headscale noise key, SSH host keys.
# age-encrypt it to pve1's key once backup-and-dr/04 settles key escrow.
backup_dir=/var/opt/backups/full
install -d -m 700 -o autoadmin -g autoadmin "$backup_dir"
umask 077
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
archive="${backup_dir}/vpnsvcs-full-$(date +%Y-%m-%dT%H%M%S).tar.zst"

# Headscale's DB is in WAL mode, so copying its files mid-write can capture a torn
# state. .backup snapshots it consistently while headscale keeps serving.
db=/var/lib/headscale/db.sqlite
sqlite3 "$db" ".backup '${stage}/db.sqlite'"
chown --reference="$db" "${stage}/db.sqlite"
chmod --reference="$db" "${stage}/db.sqlite"

# --one-file-system leaves out /proc, /sys, /dev, /run and the /tmp tmpfs but keeps
# their mount points. The snapshot is stored under the live DB's name, which is
# excluded along with its WAL files; excludes match names before --transform.
set +e
tar --create --one-file-system --numeric-owner --acls --xattrs --sparse \
    --exclude="./${db#/}" --exclude="./${db#/}-wal" --exclude="./${db#/}-shm" \
    --exclude=./var/opt/backups \
    --exclude='./var/cache/apt/*' --exclude='./var/lib/apt/lists/*' \
    --exclude='./var/tmp/*' --exclude='./tmp/*' \
    --transform="flags=r;s|^db\.sqlite\$|./${db#/}|" \
    --directory=/ . --directory="$stage" db.sqlite \
  | zstd -q -T0 -o "${archive}.tmp"
status=("${PIPESTATUS[@]}")
set -e
# tar exits 1 when a file changed while it was read (logs, the journal). The archive
# is still whole, and the one file that must be consistent is the DB snapshot.
if (( status[0] > 1 || status[1] != 0 )); then
  rm -f "${archive}.tmp"
  echo "error: archive failed (tar ${status[0]}, zstd ${status[1]})" >&2
  exit 1
fi

# Reads the whole archive back, which also proves it decompresses
if [[ $(zstd -dc "${archive}.tmp" | tar --list | grep -cx "\./${db#/}\(-wal\|-shm\)\?") != 1 ]]; then
  rm -f "${archive}.tmp"
  echo "error: archive doesn't hold exactly one copy of ${db}" >&2
  exit 1
fi

mv "${archive}.tmp" "$archive"
chown autoadmin:autoadmin "$archive"
chmod 400 "$archive"
# Keep the newest 2; the disk is small and pve1 keeps the history. The ISO timestamp
# makes name order chronological.
find "$backup_dir" -maxdepth 1 -name 'vpnsvcs-full-*.tar.zst' | sort | head -n -2 | xargs -r rm -f
ls -lh "$archive"
