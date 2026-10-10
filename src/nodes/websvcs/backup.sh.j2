#!/bin/bash
# websvcs backup: the config and small state of every service, staged under
# /var/opt/backups for pve1's backup_orchestrator to pull.
# Usage:
#   src/websvcs/backup.sh
# Not staged, on purpose: /var/opt/archivebox (large, re-archivable), the chromium
# volume (browser profile), the whisper/piper/openwakeword model caches (downloaded on
# start), and the media array under /srv/media and its member disks:
# snapraid parity is the media's only protection. Guacamole's state is in Postgres on
# secsvcs. The homesite releases are in the homesite repo; only the live release is
# kept here.

set -euo pipefail
# shellcheck source=src/debian/backup_lib.sh
source /root/homelab-rendered/src/debian/backup_lib.sh

stage_init

excludes+=(--exclude=etc/opt/wyoming/src --exclude=etc/opt/novnc/src
  --exclude=etc/opt/finance_exporter/src)
stage_paths /etc/opt /etc/ssh /etc/systemd/system /etc/containers/systemd \
  /etc/snapraid.conf /etc/fstab "$(realpath /var/opt/nginx/www)"
# Isso comments, SQLite under a running process; a live copy is acceptable.
stage_volume issodb

stage_finish
