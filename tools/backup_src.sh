#!/usr/bin/env bash
# ./tools/backup_src.sh /path/to/backup.tar.gz

set -euo pipefail

# Run from root of project directory, 1st arg is destination

tar -zcf /tmp/homelab_src_backup.tar.gz .
mv /tmp/homelab_src_backup.tar.gz "$1"
