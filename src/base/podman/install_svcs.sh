#!/bin/bash
# Installs the platform services every container VM runs, for this node: the services
# its inventory marks `shared: true`. The hostname is the node name.
# Usage:
#   src/base/podman/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

node=$(hostname -s)

cd "$rendered"
watch_homelab_units

# Every image the case's quadlets name is downloaded (or built) and passes the scan gate
# before any quadlet is copied; a blocked image stops the install here.
/usr/local/bin/image_updater install "${1:?usage: $0 SERVICE_NAME}"

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    # Emptied first so routes deleted from the repo stop being served
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic "nodes/${node}/traefik/"*.yml services/traefik/dynamic/*.yml
    install -D -m 644 services/traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    rm -rf /etc/opt/traefik/plugins-local
    cp -r services/traefik/plugins-local /etc/opt/traefik/
    base/podman/render_host.sh services/traefik/traefik.container
    install_quadlet services/traefik/traefik.container
    # The node's own additions to the quadlet, if any. Replaced whole, so a drop-in
    # deleted from the repo stops applying.
    rm -rf /etc/containers/systemd/traefik.container.d
    if [ -d "nodes/${node}/traefik/traefik.container.d" ]; then
      install -D -m 644 -t /etc/containers/systemd/traefik.container.d "nodes/${node}/traefik/traefik.container.d/"*
    fi
    reload_restart traefik
    ;;
  crowdsec_appsec)
    # The client certificate and key come from install_certs/install_keys.
    ls /etc/opt/crowdsec_appsec/certificates/appsec.key.pem
    install -D -m 644 -t /etc/opt/crowdsec_appsec/config/acquis.d services/crowdsec/appsec.yaml
    install -D -m 644 services/crowdsec/allowlist.yaml \
      /etc/opt/crowdsec_appsec/config/parsers/s02-enrich/homelab-allowlist.yaml
    base/podman/render_host.sh services/crowdsec/crowdsec_appsec.container
    install_quadlet services/crowdsec/crowdsec_appsec.container services/crowdsec/appsecdata.volume
    reload_restart crowdsec_appsec
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent "nodes/${node}/prometheus.yml"
    base/podman/render_host.sh services/victoriametrics/vmagent.container
    install_quadlet services/victoriametrics/vmagent.container services/victoriametrics/vmagentdata.volume
    reload_restart vmagent
    ;;
  fluentbit)
    install -D -m 644 services/fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit services/fluentbit/journald.lua
    install -D -m 644 base/debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    base/podman/render_host.sh services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    reload_restart fluentbit
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
