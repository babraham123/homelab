#!/usr/bin/env bash
# Installs websvcs specific systemd services.
# Usage:
#   src/websvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src
mkdir -p /etc/containers/systemd

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/config/dynamic
    mkdir -p /etc/opt/traefik/config/static
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
  dashy)
    mkdir -p /etc/opt/dashy/config
    cp dashy/dashy.yml /etc/opt/dashy/config
    cp dashy/dashy.container /etc/containers/systemd
    ;;
  fluentbit)
    cp debian/list_services.sh /usr/local/bin
    mkdir -p /etc/opt/fluentbit
    cp victorialogs/fluentbit.conf /etc/opt/fluentbit/config_template.conf
    cp victorialogs/fluentbit_prestart.sh /etc/opt/fluentbit/prestart.sh
    cp victorialogs/fluentbit.container /etc/containers/systemd
    ;;
  *)
    echo "Unknown service: $1"
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl restart "$1"
systemctl status "$1"
