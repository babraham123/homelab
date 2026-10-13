#!/bin/bash
# pve1 backup: stages the host's trust roots and config under /var/opt/backups (the
# orchestrator copies it into /root/backups/pve1 like any other node's stage), then
# backs up every VM on this host to PBS through the API.
# Usage:
#   src/nodes/pve1/backup.sh
# pve1 is the one host nothing else can restore: the AGE key, private CA, SSH CA and
# every secrets file live here, outside any VM. docs/guides/pve1_recovery.md lists them.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# shellcheck source=src/base/debian/backup_lib.sh
source "${rendered}/base/debian/backup_lib.sh"

# Root owned: the pull is local, so nothing here needs to be readable by autoadmin.
stage_init
# All of /etc, so no host config is missed. It includes /etc/pve, the pmxcfs mount:
# storage.cfg and the PBS credentials under priv/, VM configs, users. Reading it is
# fine; it just doesn't take chmod.
stage_paths /etc /root/secrets /root/ca /root/ssh /root/acme /root/.ssh \
  /var/lib/vz/snippets /usr/local/bin
stage_send

# router, secsvcs, homesvcs.
vzdump_to pbs2 --all 1
