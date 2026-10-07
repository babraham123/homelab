#!/bin/bash
# pve1 backup: stages the host's trust roots and config under /var/opt/backups (the
# orchestrator copies it into /root/backups/pve1 like any other node's stage), then
# backs up every VM on this host to PBS through the API.
# Usage:
#   src/pve1/backup.sh
# pve1 is the one host nothing else can restore: the AGE key, private CA, SSH CA and
# every secrets file live here, outside any VM. docs/guides/pve1_recovery.md lists them.

set -euo pipefail
# shellcheck source=src/debian/backup_lib.sh
source /root/homelab-rendered/src/debian/backup_lib.sh

# Root owned: the pull is local, so nothing here needs to be readable by autoadmin.
stage_init root
# /etc/pve is the pmxcfs mount: storage.cfg and the PBS credentials under priv/,
# VM configs, users. Reading it is fine; it just doesn't take chmod.
stage_paths /etc/pve /etc/network/interfaces /etc/resolv.conf /etc/hosts /etc/hostname \
  /etc/ssh /etc/msmtprc /etc/aliases /etc/opt /etc/systemd/system \
  /root/secrets /root/ca /root/ssh /root/acme /root/.ssh \
  /var/lib/vz/snippets /usr/local/bin
stage_finish

# router, secsvcs, homesvcs. Snapshot mode keeps them running; PBS stores only the
# chunks that changed since the last run.
upid=$(pvesh create "/nodes/$(hostname)/vzdump" --all 1 --storage pbs2 --mode snapshot \
  --notes-template '{{guestname}}')
pve_task "$upid"
