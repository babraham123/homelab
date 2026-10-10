#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/base/debian/install_svcs.sh SERVICE_NAME

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /root/homelab-rendered/src

case $1 in
  cert_notifier)
    install -D -t /usr/local/bin base/certificates/cert_notifier.sh
    install -D -m 644 -t /etc/systemd/system base/certificates/cert_notifier.{service,timer}

    systemctl daemon-reload
    systemctl enable cert_notifier.service
    systemctl enable cert_notifier.timer
    systemctl restart cert_notifier.timer
    exit 0
    ;;
  backup_orchestrator)
    # The client uploads /root/backups to PBS as a host backup.
    apt-get install -y proxmox-backup-client
    install -D -t /usr/local/bin nodes/pve1/backup_orchestrator.sh
    install -D -m 644 -t /etc/systemd/system nodes/pve1/backup_orchestrator.{service,timer}

    # Only the timer is enabled; the service is a oneshot it triggers.
    systemctl daemon-reload
    systemctl enable backup_orchestrator.timer
    systemctl restart backup_orchestrator.timer
    exit 0
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac
