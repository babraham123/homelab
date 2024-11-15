#!/usr/bin/env bash
# Installs websvcs specific systemd services.
# Usage:
#   src/websvcs/install_svcs.sh SERVICE_NAME

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
    cp websvcs/traefik/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/dynamic/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    cp websvcs/traefik/traefik.container /etc/containers/systemd
    ;;
  vmagent)
    mkdir -p /etc/opt/vmagent
    cp websvcs/prometheus.yml /etc/opt/vmagent
    cp victoriametrics/vmagent.container /etc/containers/systemd
    cp victoriametrics/vmagentdata.volume /etc/containers/systemd
    ;;
  nginx)
    mkdir -p /etc/opt/nginx/conf
    mkdir -p /var/opt/nginx/www/www
    mkdir -p /var/opt/nginx/www/error
    cp nginx/nginx.conf /etc/opt/nginx/conf
    cp nginx/index.html /var/opt/nginx/www/www
    cp nginx/404.html /var/opt/nginx/www/error
    cp nginx/nginx.container /etc/containers/systemd
    ;;
  homepage)
    mkdir -p /etc/opt/homepage/config
    cp homepage/*.yaml /etc/opt/homepage/config
    chown -R 1000:1000 /etc/opt/homepage/config
    chmod -R 744 /etc/opt/homepage/config
    cp -r homepage/images /etc/opt/homepage
    cp homepage/homepage.container /etc/containers/systemd
    ;;
  finance_exporter)
    mkdir -p /etc/opt/finance_exporter/src
    cp finance_exporter/config.yaml /etc/opt/finance_exporter
    cp finance_exporter/finance_exporter.container /etc/containers/systemd
    # Build image, TODO: generalize this
    wget "https://github.com/babraham123/finance-exporter/archive/refs/heads/main.tar.gz" -O - | \
      tar -xz -C /etc/opt/finance_exporter/src --strip-components=1
    podman build -t finance_exporter /etc/opt/finance_exporter/src
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
