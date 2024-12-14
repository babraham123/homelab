#!/usr/bin/env bash
# Installs homesvcs specific systemd services.
# Usage:
#   src/homesvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src
mkdir -p /etc/containers/systemd
cp podman/*.sh /usr/local/bin

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/config/dynamic
    mkdir -p /etc/opt/traefik/config/static
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    cp homesvcs/traefik/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/dynamic/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    cp homesvcs/traefik/traefik.container /etc/containers/systemd
    ;;
  fluentbit)
    mkdir -p /etc/opt/fluentbit
    cp fluentbit/config.yaml.j2 /etc/opt/fluentbit
    cp fluentbit/journald.lua /etc/opt/fluentbit
    cp fluentbit/fluentbit.container /etc/containers/systemd
    cp fluentbit/fbdata.volume /etc/containers/systemd
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl restart "$1"
systemctl status "$1"
