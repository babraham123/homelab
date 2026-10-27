#!/bin/bash
# Installs secsvcs specific systemd services.
# Usage:
#   src/nodes/secsvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cd "$rendered"
watch_homelab_units

# Every image the case's quadlets name is downloaded (or built) and passes the scan gate
# before any quadlet is copied; a blocked image stops the install here.
/usr/local/bin/image_updater install "${1:?usage: $0 SERVICE_NAME}"

case $1 in
  postgres)
    mkdir -p /etc/opt/db/certificates
    install -D -m 644 -t /var/opt/db services/postgres/pg_init.sql
    install -D -m 644 -t /etc/opt/db services/postgres/pg_hba.conf
    install_quadlet services/postgres/postgres.container services/postgres/postgres18.volume
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
    install -D -m 644 -t /etc/opt/grafana services/grafana/grafana.ini services/grafana/datasources.yml services/grafana/dashboard.yml
    # Clear old dashboards so ones deleted from the repo stop being provisioned
    rm -f /etc/opt/grafana/dashboards/*.json
    install -D -m 644 -t /etc/opt/grafana/dashboards services/grafana/dashboards/*.json
    install_quadlet services/grafana/grafana.container services/grafana/grafanadata.volume
    reload_restart grafana
    ;;
  vaultwarden)
    mkdir -p /etc/opt/vaultwarden/certificates
    install_quadlet services/vaultwarden/vaultwarden.container services/vaultwarden/vaultwardendata.volume
    reload_restart vaultwarden
    ;;
  ntfy_idp_push)
    # LLDAP's CA chain comes from install_certs
    ls /etc/opt/lldap/certificates/ca.chain.pem
    install -D -m 644 -t /etc/opt/ntfy_idp_push services/ntfy_idp_push/server.yml
    install_quadlet services/ntfy_idp_push/ntfy_idp_push.container services/ntfy_idp_push/ntfy_idp_push.volume
    reload_restart ntfy_idp_push
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
  crowdsec)
    # The certificate and key come from install_certs/install_keys
    ls /etc/opt/crowdsec/certificates/crowdsec.key.pem
    install -D -m 644 -t /etc/opt/crowdsec/config/acquis.d services/crowdsec/victorialogs.yaml
    install -D -m 644 -t /etc/opt/crowdsec/config services/crowdsec/config.yaml.local
    install -D -m 644 services/crowdsec/allowlist.yaml /etc/opt/crowdsec/config/parsers/s02-enrich/homelab-allowlist.yaml
    install_quadlet services/crowdsec/crowdsec.container services/crowdsec/crowdsecdb.volume
    reload_restart crowdsec
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
