#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/nodes/pve1/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

cd "$rendered"

case $1 in
  cert_notifier)
    install_bin base/certificates/cert_notifier.sh
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
    # The unit runs the script in place, so a deploy updates it together with the
    # backup_lib.sh it sources; a copy in /usr/local/bin would lag behind.
    rm -f /usr/local/bin/backup_orchestrator.sh
    install -D -m 644 -t /etc/systemd/system nodes/pve1/backup_orchestrator.{service,timer}

    # Only the timer is enabled; the service is a oneshot it triggers.
    systemctl daemon-reload
    systemctl enable backup_orchestrator.timer
    systemctl restart backup_orchestrator.timer
    exit 0
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
