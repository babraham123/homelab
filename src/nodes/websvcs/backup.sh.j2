#!/bin/bash
# websvcs backup: the config and small state of every service, staged under
# /var/opt/backups for pve1's backup_orchestrator to pull.
# Usage:
#   src/nodes/websvcs/backup.sh
# Not staged, on purpose: /var/opt/archivebox (large, re-archivable), the chromium
# volume (browser profile), the whisper/piper/openwakeword model caches (downloaded on
# start), and the media array under /srv/media and its member disks:
# snapraid parity is the media's only protection. Guacamole's state is in Postgres on
# secsvcs. The homesite releases are in the homesite repo; only the live release is
# kept here.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

stage_init

excludes+=(--exclude=etc/opt/wyoming/src --exclude=etc/opt/novnc/src
  --exclude=etc/opt/finance_exporter/src)
stage_paths /etc/opt /etc/ssh /etc/systemd/system /etc/containers/systemd \
  /etc/snapraid.conf /etc/fstab "$(realpath /var/opt/nginx/www)"
# Isso comments, SQLite under a running process; a live copy is acceptable.
stage_volume issodb

stage_send
