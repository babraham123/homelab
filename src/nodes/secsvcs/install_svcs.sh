#!/bin/bash
# Installs secsvcs specific systemd services.
# Usage:
#   src/nodes/secsvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/svcs_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/svcs_lib.sh"

cd "$rendered"

case $1 in
  postgres)
    mkdir -p /etc/opt/db/certificates
    install -D -m 644 -t /var/opt/db services/postgres/pg_init.sql
    install_quadlet services/postgres/postgres.container services/postgres/postgresdb.volume
    reload_restart postgres
    ;;
  lldap)
    mkdir -p /etc/opt/lldap/certificates
    install -D -m 644 -t /etc/opt/lldap services/lldap/lldap_config.toml
    install_quadlet services/lldap/lldap.container
    reload_restart lldap
    ;;
  authelia)
    mkdir -p /etc/opt/authelia/certificates
    install -D -m 644 -t /etc/opt/authelia/config services/authelia/configuration.yml
    install_quadlet services/authelia/authelia.container
    reload_restart authelia
    ;;
  traefik)
    install_traefik_config secsvcs
    install_quadlet nodes/secsvcs/traefik/traefik.container
    reload_restart traefik
    ;;
  victoriametrics)
    install -D -m 644 -t /etc/opt/victoriametrics nodes/secsvcs/prometheus.yml
    install_quadlet services/victoriametrics/victoriametrics.container services/victoriametrics/vmdata.volume
    reload_restart victoriametrics
    ;;
  victorialogs)
    mkdir -p /etc/opt/victorialogs
    install_quadlet services/victorialogs/victorialogs.container services/victorialogs/vldata.volume
    reload_restart victorialogs
    ;;
  gatus)
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /var/opt/gatus
    install -D -m 644 -t /etc/opt/gatus services/gatus/config.yaml
    install_quadlet services/gatus/gatus.container
    reload_restart gatus
    ;;
  vmalert)
    rm -f /etc/opt/vmalert/*.yml
    install -D -m 644 -t /etc/opt/vmalert services/vmalert/configs/*.yml
    install_quadlet services/vmalert/vmalert.container
    reload_restart vmalert
    ;;
  alertmanager)
    install -D -m 644 -t /etc/opt/alertmanager services/alertmanager/config.yml.j2 services/alertmanager/web_config.yml.j2
    install_quadlet services/alertmanager/alertmanager.container
    reload_restart alertmanager
    ;;
  ntfy-alertmanager)
    install -D -m 644 services/alertmanager/ntfy-alertmanager.scfg.j2 /etc/opt/ntfy-alertmanager/config.scfg.j2
    install_quadlet services/alertmanager/ntfy-alertmanager.container
    reload_restart ntfy-alertmanager
    ;;
  ntfy)
    mkdir -p /var/opt/ntfy
    install -D -m 644 -t /etc/opt/ntfy services/ntfy/config.yml.j2
    install_quadlet services/ntfy/ntfy.container services/ntfy/ntfydb.volume
    reload_restart ntfy
    ;;
  grafana)
    mkdir -p /etc/opt/grafana/certificates
    chown -R 472:0 /var/opt/grafana
    install -D -m 644 -t /etc/opt/grafana services/grafana/grafana.ini services/grafana/datasources.yml services/grafana/dashboard.yml
    # Clear old dashboards so ones deleted from the repo stop being provisioned
    rm -f /etc/opt/grafana/dashboards/*.json
    install -D -m 644 -t /etc/opt/grafana/dashboards services/grafana/dashboards/*.json
    install_quadlet services/grafana/grafana.container services/grafana/grafanadata.volume
    reload_restart grafana
    ;;
  vault)
    echo "TODO: Implement vault"
    # install_quadlet vault/vault.container
    # reload_restart vault
    ;;
  olive_tin)
    # ssh keys should already be in place
    ls /etc/opt/olive_tin/ssh/id_ed25519-cert.pub
    install -D -m 644 -t /etc/opt/olive_tin/config services/olive_tin/config.yaml
    install -D -m 644 base/debian/ssh_config /etc/opt/olive_tin/ssh/config
    touch /etc/opt/olive_tin/config/sessions.yaml
    chown -R 1000:1000 /etc/opt/olive_tin
    install_quadlet services/olive_tin/olive_tin.container
    reload_restart olive_tin
    ;;
  fluentbit)
    install_fluentbit_config nodes/secsvcs/fluentbit.yaml.j2
    base/podman/render_host.sh secsvcs services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    reload_restart fluentbit
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
