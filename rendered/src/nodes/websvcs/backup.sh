#!/bin/bash
# websvcs backup: the config and small state of every service, staged under
# /var/opt/backups for pve1's backup_orchestrator to pull.
# Usage:
#   src/nodes/websvcs/backup.sh
# Not staged, on purpose: the whisper/piper/openwakeword and Calliope model caches
# (downloaded on use), Storyteller's caches (rebuilt from the library), and the media
# array under /srv/media and its member disks: snapraid parity is the media's only
# protection, the web archive (linkding snapshots, Readeck articles), read-along books
# and Storyteller's processed books and uploads included. Guacamole's state is in
# Postgres on secsvcs. The homesite releases are in the homesite repo; only the live
# release is kept here.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

stage_init

# Each live DB is snapshotted; its files are excluded from the trees below.
dump_sqlite linkding /var/opt/linkding/db.sqlite3
dump_sqlite readeck /var/opt/readeck/data/db.sqlite3
dump_sqlite storyteller /var/opt/storyteller/storyteller.db

excludes+=(--exclude=etc/opt/wyoming/src
  --exclude=etc/opt/finance_exporter/src
  --exclude='var/opt/linkding/db.sqlite3*'
  --exclude='var/opt/readeck/data/db.sqlite3*'
  --exclude='var/opt/storyteller/storyteller.db*'
  --exclude=var/opt/storyteller/cache
  --exclude=var/opt/storyteller/image-cache)
# Readeck's config.toml holds the secret key its API tokens are signed with.
stage_paths /etc/opt /etc/ssh /etc/systemd/system /etc/containers/systemd \
  /etc/snapraid.conf /etc/fstab "$(realpath /var/opt/nginx/www)" \
  /var/opt/linkding /var/opt/readeck /var/opt/storyteller /var/opt/bookmark_handoff
# Isso comments, SQLite under a running process; a live copy is acceptable.
stage_volume issodb

stage_send
