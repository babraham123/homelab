#!/bin/bash
# Native HA backup, restorable across HA versions (unlike the VM image), copied to
# /var/opt/backups/hass. Keeps the newest 8.
# Usage:
#   src/homesvcs/backup_hass.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

# The recorder DB lives in hassdb (/data), outside /config, so history is not
# in this archive; it only rides in the VM backup.
# Ref: https://www.home-assistant.io/integrations/backup/
token=$(/usr/local/bin/get_secret.sh hass_backup_token)
if [[ -z "$token" || "$token" == "null" ]]; then
  echo "error: hass_backup_token secret is not set" >&2
  exit 1
fi
volpath=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-hassconfig)
dest=/var/opt/backups/hass
install -d -m 700 "$dest"
marker=$(mktemp)
trap 'rm -f "$marker"' EXIT

# The REST call blocks until the backup is written; the token goes via stdin
# so it stays out of the process list. Needs an admin user's token.
printf 'header = "Authorization: Bearer %s"\n' "$token" | \
  curl -sS --fail-with-body --max-time 1800 -K - -X POST \
  http://10.12.0.11:8123/api/services/backup/create
echo

archive=$(find "$volpath/backups" -maxdepth 1 -name 'Custom_backup_*.tar' \
  -newer "$marker" -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)
if [[ -z "$archive" ]]; then
  echo "error: no new backup archive in $volpath/backups" >&2
  exit 1
fi
cp "$archive" "$dest/"
chmod 600 "$dest/$(basename "$archive")"
echo "Copied $(basename "$archive") to $dest"

# backup.create has no retention of its own. Keep only the newest custom
# backup in HA so the volume (and every vzdump of it) stays small.
find "$volpath/backups" -maxdepth 1 -name 'Custom_backup_*.tar' \
  ! -path "$archive" -delete
find "$dest" -maxdepth 1 -name '*.tar' -printf '%T@ %p\n' | sort -rn | \
  tail -n +9 | cut -d' ' -f2- | xargs -r -d '\n' rm -f --
