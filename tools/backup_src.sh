#!/usr/bin/env bash
# Backs up the source code to a tarball at the given location.
# Run from root of the project directory.
# Usage:
#   ./tools/backup_src.sh /path/to/backup.tar.gz

set -euo pipefail

tar -zcf /tmp/homelab_src_backup.tar.gz .
mv /tmp/homelab_src_backup.tar.gz "$1"
