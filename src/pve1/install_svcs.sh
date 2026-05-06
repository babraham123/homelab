#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/debian/install_svcs.sh SERVICE_NAME

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /root/homelab-rendered/src

case $1 in
  cert_notifier)
    cp certificates/cert_notifier.sh /usr/local/bin
    cp certificates/cert_notifier.service /etc/systemd/system
    cp certificates/cert_notifier.timer /etc/systemd/system

    systemctl daemon-reload
    systemctl enable cert_notifier.service
    systemctl enable cert_notifier.timer
    systemctl restart cert_notifier.timer
    exit 0
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl enable "$1"
systemctl restart "$1"
systemctl status "$1"
