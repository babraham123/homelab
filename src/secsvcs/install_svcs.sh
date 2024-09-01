#!/usr/bin/env bash
# Installs secsvcs specific systemd services.
# Usage:
#   src/secsvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src
mkdir -p /etc/containers/systemd

case $1 in
  postgres)
    mkdir -p /etc/opt/db/certificates
    cp postgres/pg_init.sql /var/opt/db
    cp postgres/postgres.container /etc/containers/systemd
    cp postgres/postgresdb.volume /etc/containers/systemd
    ;;
  lldap)
    mkdir -p /etc/opt/lldap/certificates
    cp lldap/lldap_config.toml /etc/opt/lldap
    cp lldap/lldap.container /etc/containers/systemd
    ;;
  authelia)
    mkdir -p /etc/opt/authelia/config
    mkdir -p /etc/opt/authelia/certificates
    cp authelia/configuration.yml /etc/opt/authelia/config
    cp authelia/authelia.container /etc/containers/systemd
    ;;
  traefik)
    mkdir -p /etc/opt/traefik/config/dynamic
    mkdir -p /etc/opt/traefik/config/static
    rm -rf /etc/opt/traefik/config/dynamic/*
    cp secsvcs/traefik/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/dynamic/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    cp secsvcs/traefik/traefik.container /etc/containers/systemd
    ;;
  victoriametrics)
    mkdir -p /etc/opt/victoriametrics
    cp secsvcs/prometheus.yml /etc/opt/victoriametrics
    cp victoriametrics/victoriametrics.container /etc/containers/systemd
    cp victoriametrics/vmdata.volume /etc/containers/systemd
    ;;
  victorialogs)
    mkdir -p /etc/opt/victorialogs
    cp victorialogs/victorialogs.container /etc/containers/systemd
    cp victorialogs/vldata.volume /etc/containers/systemd
    ;;
  gatus)
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /var/opt/gatus
    cp gatus/config.yaml /etc/opt/gatus
    chmod 600 /etc/opt/gatus/config.yaml
    cp gatus/runner.sh /etc/opt/gatus
    cp gatus/authelia_login.sh /etc/opt/gatus
    wget --output-document=/var/opt/gatus/busybox "https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    chmod +x /var/opt/gatus/busybox
    CU_VERSION=$(curl -s "https://api.github.com/repos/moparisthebest/static-curl/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=/var/opt/gatus/curl "https://github.com/moparisthebest/static-curl/releases/download/v$CU_VERSION/curl-amd64"
    chmod +x /var/opt/gatus/curl
    cp gatus/gatus.container /etc/containers/systemd
    ;;
  pve_exporter)
    mkdir -p /etc/opt/pve_exporter
    cp exporter/pve.yml /etc/opt/pve_exporter
    # chown 101:101 /etc/opt/pve_exporter/*
    # https://github.com/prometheus-pve/prometheus-pve-exporter/blob/main/Dockerfile
    cp exporter/pve_exporter.container /etc/containers/systemd
    ;;
  alertmanager)
    mkdir -p /etc/opt/alertmanager
    cp alert/alertmanager.yml /etc/opt/alertmanager/config.yml
    cp alert/alertmanager.container /etc/containers/systemd
    ;;
  vmalert)
    mkdir -p /etc/opt/vmalert
    rm -f /etc/opt/vmalert/*.yml
    cp alert/configs/*.yml /etc/opt/vmalert
    cp alert/vmalert.container /etc/containers/systemd
    ;;
  grafana)
    mkdir -p /etc/opt/grafana/certificates
    mkdir -p /var/opt/grafana/plugins
    chown -R 472:0 /var/opt/grafana
    cp grafana/grafana.ini /etc/opt/grafana
    cp grafana/ldap.toml /etc/opt/grafana
    cp grafana/datasources.yml /etc/opt/grafana
    cp grafana/dashboard.yml /etc/opt/grafana
    cp grafana/vm_download.sh /etc/opt/grafana
    cp -r grafana/dashboards /etc/opt/grafana
    cp grafana/grafana.container /etc/containers/systemd
    cp grafana/grafanadata.volume /etc/containers/systemd
    ;;
  vault)
    echo "TODO: Implement vault"
    # cp vault/vault.container /etc/containers/systemd
    exit 0
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
