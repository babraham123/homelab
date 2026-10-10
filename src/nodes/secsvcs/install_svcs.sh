#!/bin/bash
# Installs secsvcs specific systemd services.
# Usage:
#   src/secsvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

case $1 in
  postgres)
    mkdir -p /etc/opt/db/certificates
    install -D -m 644 -t /var/opt/db postgres/pg_init.sql
    install -D -m 644 -t /etc/containers/systemd postgres/postgres.container postgres/postgresdb.volume
    ;;
  lldap)
    mkdir -p /etc/opt/lldap/certificates
    install -D -m 644 -t /etc/opt/lldap lldap/lldap_config.toml
    install -D -m 644 -t /etc/containers/systemd lldap/lldap.container
    ;;
  authelia)
    mkdir -p /etc/opt/authelia/certificates
    install -D -m 644 -t /etc/opt/authelia/config authelia/configuration.yml
    install -D -m 644 -t /etc/containers/systemd authelia/authelia.container
    ;;
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic secsvcs/traefik/*.yml traefik/dynamic/*.yml
    install -D -m 644 traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    install -D -m 644 -t /etc/containers/systemd secsvcs/traefik/traefik.container
    ;;
  victoriametrics)
    install -D -m 644 -t /etc/opt/victoriametrics secsvcs/prometheus.yml
    install -D -m 644 -t /etc/containers/systemd victoriametrics/victoriametrics.container victoriametrics/vmdata.volume
    ;;
  victorialogs)
    mkdir -p /etc/opt/victorialogs
    install -D -m 644 -t /etc/containers/systemd victorialogs/victorialogs.container victorialogs/vldata.volume
    ;;
  gatus)
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /var/opt/gatus
    install -D -m 644 -t /etc/opt/gatus gatus/config.yaml
    install -D -m 644 -t /etc/containers/systemd gatus/gatus.container
    ;;
  vmalert)
    rm -f /etc/opt/vmalert/*.yml
    install -D -m 644 -t /etc/opt/vmalert vmalert/configs/*.yml
    install -D -m 644 -t /etc/containers/systemd vmalert/vmalert.container
    ;;
  alertmanager)
    install -D -m 644 -t /etc/opt/alertmanager alertmanager/config.yml.j2 alertmanager/web_config.yml.j2
    install -D -m 644 -t /etc/containers/systemd alertmanager/alertmanager.container
    ;;
  ntfy-alertmanager)
    install -D -m 644 alertmanager/ntfy-alertmanager.scfg.j2 /etc/opt/ntfy-alertmanager/config.scfg.j2
    install -D -m 644 -t /etc/containers/systemd alertmanager/ntfy-alertmanager.container
    ;;
  ntfy)
    mkdir -p /var/opt/ntfy
    install -D -m 644 -t /etc/opt/ntfy ntfy/config.yml.j2
    install -D -m 644 -t /etc/containers/systemd ntfy/ntfy.container ntfy/ntfydb.volume
    ;;
  grafana)
    mkdir -p /etc/opt/grafana/certificates
    chown -R 472:0 /var/opt/grafana
    install -D -m 644 -t /etc/opt/grafana grafana/grafana.ini grafana/datasources.yml grafana/dashboard.yml
    # Clear old dashboards so ones deleted from the repo stop being provisioned
    rm -f /etc/opt/grafana/dashboards/*.json
    install -D -m 644 -t /etc/opt/grafana/dashboards grafana/dashboards/*.json
    install -D -m 644 -t /etc/containers/systemd grafana/grafana.container grafana/grafanadata.volume
    ;;
  vault)
    echo "TODO: Implement vault"
    # install -D -m 644 -t /etc/containers/systemd vault/vault.container
    exit 0
    ;;
  olive_tin)
    # ssh keys should already be in place
    ls /etc/opt/olive_tin/ssh/id_ed25519-cert.pub
    install -D -m 644 -t /etc/opt/olive_tin/config olive_tin/config.yaml
    install -D -m 644 debian/ssh_config /etc/opt/olive_tin/ssh/config
    touch /etc/opt/olive_tin/config/sessions.yaml
    chown -R 1000:1000 /etc/opt/olive_tin
    install -D -m 644 -t /etc/containers/systemd olive_tin/olive_tin.container
    ;;
  fluentbit)
    install -D -m 644 secsvcs/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit fluentbit/journald.lua
    install -D -m 644 debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    /root/homelab-rendered/src/podman/render_host.sh secsvcs fluentbit/fluentbit.container
    install -D -m 644 -t /etc/containers/systemd fluentbit/fluentbit.container fluentbit/fbdata.volume
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl restart "$1"
systemctl status "$1" --no-pager
