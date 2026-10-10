#!/bin/bash
# Installs secsvcs specific systemd services.
# Usage:
#   src/nodes/secsvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cd "$rendered"

case $1 in
  postgres)
    mkdir -p /etc/opt/db/certificates
    install -D -m 644 -t /var/opt/db services/postgres/pg_init.sql
    install_quadlet services/postgres/postgres.container services/postgres/postgresdb.volume
    ;;
  lldap)
    mkdir -p /etc/opt/lldap/certificates
    install -D -m 644 -t /etc/opt/lldap services/lldap/lldap_config.toml
    install_quadlet services/lldap/lldap.container
    ;;
  authelia)
    mkdir -p /etc/opt/authelia/certificates
    install -D -m 644 -t /etc/opt/authelia/config services/authelia/configuration.yml
    install_quadlet services/authelia/authelia.container
    ;;
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic nodes/secsvcs/traefik/*.yml services/traefik/dynamic/*.yml
    install -D -m 644 services/traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    install_quadlet nodes/secsvcs/traefik/traefik.container
    ;;
  victoriametrics)
    install -D -m 644 -t /etc/opt/victoriametrics nodes/secsvcs/prometheus.yml
    install_quadlet services/victoriametrics/victoriametrics.container services/victoriametrics/vmdata.volume
    ;;
  victorialogs)
    mkdir -p /etc/opt/victorialogs
    install_quadlet services/victorialogs/victorialogs.container services/victorialogs/vldata.volume
    ;;
  gatus)
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /var/opt/gatus
    install -D -m 644 -t /etc/opt/gatus services/gatus/config.yaml
    install_quadlet services/gatus/gatus.container
    ;;
  vmalert)
    rm -f /etc/opt/vmalert/*.yml
    install -D -m 644 -t /etc/opt/vmalert services/vmalert/configs/*.yml
    install_quadlet services/vmalert/vmalert.container
    ;;
  alertmanager)
    install -D -m 644 -t /etc/opt/alertmanager services/alertmanager/config.yml.j2 services/alertmanager/web_config.yml.j2
    install_quadlet services/alertmanager/alertmanager.container
    ;;
  ntfy-alertmanager)
    install -D -m 644 services/alertmanager/ntfy-alertmanager.scfg.j2 /etc/opt/ntfy-alertmanager/config.scfg.j2
    install_quadlet services/alertmanager/ntfy-alertmanager.container
    ;;
  ntfy)
    mkdir -p /var/opt/ntfy
    install -D -m 644 -t /etc/opt/ntfy services/ntfy/config.yml.j2
    install_quadlet services/ntfy/ntfy.container services/ntfy/ntfydb.volume
    ;;
  grafana)
    mkdir -p /etc/opt/grafana/certificates
    chown -R 472:0 /var/opt/grafana
    install -D -m 644 -t /etc/opt/grafana services/grafana/grafana.ini services/grafana/datasources.yml services/grafana/dashboard.yml
    # Clear old dashboards so ones deleted from the repo stop being provisioned
    rm -f /etc/opt/grafana/dashboards/*.json
    install -D -m 644 -t /etc/opt/grafana/dashboards services/grafana/dashboards/*.json
    install_quadlet services/grafana/grafana.container services/grafana/grafanadata.volume
    ;;
  vault)
    echo "TODO: Implement vault"
    # install_quadlet vault/vault.container
    exit 0
    ;;
  olive_tin)
    # ssh keys should already be in place
    ls /etc/opt/olive_tin/ssh/id_ed25519-cert.pub
    install -D -m 644 -t /etc/opt/olive_tin/config services/olive_tin/config.yaml
    install -D -m 644 base/debian/ssh_config /etc/opt/olive_tin/ssh/config
    touch /etc/opt/olive_tin/config/sessions.yaml
    chown -R 1000:1000 /etc/opt/olive_tin
    install_quadlet services/olive_tin/olive_tin.container
    ;;
  fluentbit)
    install -D -m 644 nodes/secsvcs/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit services/fluentbit/journald.lua
    install -D -m 644 base/debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    base/podman/render_host.sh secsvcs services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    ;;
  *)
    die "unknown service: $1"
    ;;
esac

reload_restart "$1"
