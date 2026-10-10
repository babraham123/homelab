#!/bin/bash
# Usage:
#   src/nodes/pve1/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

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
    die "unknown command: $1"
    ;;
esac
