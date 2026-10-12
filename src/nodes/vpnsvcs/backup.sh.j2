#!/bin/bash
# vpnsvcs backup: a consistent snapshot of the Headscale database plus the state and
# config that a fresh Debian install can't regenerate, staged under /var/opt/backups
# for pve1's backup_orchestrator to pull. The OS itself is rebuilt from
# docs/guides/vpnsvcs.md; Linode's own backups cover the rest.
# Usage:
#   src/nodes/vpnsvcs/backup.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

stage_init

dump_sqlite headscale /var/lib/headscale/db.sqlite

# The live DB files are excluded in favour of the snapshot. /var/lib/headscale also
# holds the noise and DERP private keys: losing them re-registers every tailnet node.
excludes+=(--exclude='var/lib/headscale/db.sqlite*' --exclude=var/lib/headscale/cache)
stage_paths /var/lib/headscale /etc/headscale /var/lib/tailscale /etc/haproxy \
  /etc/ssh /etc/ufw /etc/opt /etc/systemd/system /etc/letsencrypt /root/.ssh

stage_send
