#!/bin/bash
# Usage:
#   src/nodes/pve1/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

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
  backup_now)
    # A run already in progress is left to finish. The manual marker makes the run
    # ignore a skip_next; the orchestrator removes it. --no-block: a run takes over an
    # hour, past OliveTin's timeout.
    if systemctl is-active --quiet backup_orchestrator.service; then
      echo "a backup_orchestrator run is already in progress"
      exit 0
    fi
    install -d -m 700 /var/lib/backup_orchestrator
    touch /var/lib/backup_orchestrator/manual
    systemctl start --no-block backup_orchestrator.service
    echo "backup_orchestrator started; the ntfy alert topic gets the summary"
    ;;
  skip_next_backup)
    "${rendered}/nodes/pve1/backup_orchestrator.sh" --skip-next
    ;;
  *)
    die "unknown command: $1"
    ;;
esac
