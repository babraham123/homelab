#!/usr/bin/env bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/debian/install_svcs.sh SERVICE_NAME

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
  vm_watchdog)
    cp pve1/vm_watchdog.sh /usr/local/bin
    cp pve1/vm_watchdog.service /etc/systemd/system
    ;;
  olive_tin)
    OT_VERSION=$(curl -s "https://api.github.com/repos/OliveTin/OliveTin/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=olive_tin.deb "https://github.com/OliveTin/OliveTin/releases/download/v${OT_VERSION}/OliveTin_linux_amd64.deb"
    dpkg --install olive_tin.deb
    rm olive_tin.deb
    cp olive_tin/config.yaml /etc/OliveTin
    rm /etc/systemd/system/OliveTin.service
    cp olive_tin/olive_tin.service /etc/systemd/system
    ;;
  node_exporter)
    NE_VERSION=$(curl -s "https://api.github.com/repos/prometheus/node_exporter/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/node_exporter-${NE_VERSION}.linux-amd64.tar.gz" -O - | tar xz
    mv "node_exporter-${NE_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${NE_VERSION}.linux-amd64"

    mkdir -p /var/lib/node_exporter/textfile_collector
    chown -R node_exporter:node_exporter /var/lib/node_exporter

    cp exporter/node_runner.sh /usr/local/bin/node_exporter_runner.sh
    chown node_exporter:node_exporter /usr/local/bin/node_exporter*
    cp exporter/node_exporter.service /etc/systemd/system
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
