#!/bin/bash
# Installs homesvcs specific systemd services.
# Usage:
#   src/nodes/homesvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cd "$rendered"

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic nodes/homesvcs/traefik/*.yml services/traefik/dynamic/*.yml
    install -D -m 644 services/traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    install_quadlet nodes/homesvcs/traefik/traefik.container
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent nodes/homesvcs/prometheus.yml
    base/podman/render_host.sh homesvcs services/victoriametrics/vmagent.container
    install_quadlet services/victoriametrics/vmagent.container services/victoriametrics/vmagentdata.volume
    ;;
  mosquitto)
    mkdir -p /etc/opt/mosquitto/certificates
    install -D -m 644 -t /etc/opt/mosquitto services/mosquitto/mosquitto.conf
    install_quadlet services/mosquitto/mosquitto.container services/mosquitto/mqttdata.volume
    ;;
  zigbee2mqtt)
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    install -D -m 644 -t /etc/opt/zigbee2mqtt/config services/zigbee2mqtt/*.yaml
    install_quadlet services/zigbee2mqtt/zigbee2mqtt.container services/zigbee2mqtt/z2mdb.volume
    ;;
  # Not in use: uncomment and add to src/nodes.yml to install again
#   esphome)
#     install -D -m 644 -t /etc/opt/esphome/config services/esphome/*.yaml
#     install_quadlet services/esphome/esphome.container
#     ;;
  home_assistant)
    mkdir -p /etc/opt/home_assistant/certs
    mkdir -p /var/opt/home_assistant/media/recordings
    install_quadlet services/home_assistant/hassconfig.volume
    systemctl daemon-reload
    systemctl start hassconfig-volume.service
    volpath=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-hassconfig)
    if [ ! -e "$volpath"/configuration.yaml ]; then
      install -m 644 -t "$volpath" services/home_assistant/*.yaml
    else
      echo "$volpath"
      ls "$volpath"
      echo -n "Have you manually updated the config files? Y or N: "
      read -r reply
      if [[ ! $reply =~ ^[Yy]$ ]]; then
        exit 1
      fi
    fi
    install_quadlet services/home_assistant/home_assistant.container services/home_assistant/hassdb.volume
    ;;
  fluentbit)
    install -D -m 644 services/fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit services/fluentbit/journald.lua
    install -D -m 644 base/debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    base/podman/render_host.sh homesvcs services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    ;;
  *)
    die "unknown service: $1"
    ;;
esac

reload_restart "$1"
