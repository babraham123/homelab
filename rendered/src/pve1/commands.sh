#!/bin/bash
# Usage:
#   src/pve1/commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

case $1 in
  archive_repo)
    # Reads a tar.gz of the repo and vars.yml from stdin (tools/deploy_src.sh pipes it
    # over ssh) into /root/backups/repo, which the weekly upload carries to PBS.
    # vars.yml is the only input to the render that isn't in git.
    dir=/root/backups/repo
    install -d -m 700 "$dir"
    archive="${dir}/homelab-$(date +%Y-%m-%dT%H%M%S).tar.gz"
    umask 077
    cat > "${archive}.tmp"
    gzip -t "${archive}.tmp"
    mv "${archive}.tmp" "$archive"
    find "$dir" -maxdepth 1 -name 'homelab-*.tar.gz' | sort | head -n -3 | xargs -r rm -f --
    ls -lh "$archive"
    ;;
  *)
    echo "error: unknown command: $1" >&2
    exit 1
    ;;
esac
