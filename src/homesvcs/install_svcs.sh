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
  vmagent)
    mkdir -p /etc/opt/vmagent
    cp homesvcs/prometheus.yml /etc/opt/vmagent
    /usr/local/bin/render_host.sh homesvcs victoriametrics/vmagent.container
    mv victoriametrics/vmagent.container /etc/containers/systemd
    cp victoriametrics/vmagentdata.volume /etc/containers/systemd
    ;;
  mosquitto)
    mkdir -p /etc/opt/mosquitto/certificates
    cp mosquitto/mosquitto.conf /etc/opt/mosquitto
    cp mosquitto/mosquitto.container /etc/containers/systemd
    cp mosquitto/mqttdata.volume /etc/containers/systemd
    ;;
  zigbee2mqtt)
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    mkdir -p /etc/opt/zigbee2mqtt/config
    cp zigbee2mqtt/*.yaml /etc/opt/zigbee2mqtt/config
    cp zigbee2mqtt/zigbee2mqtt.container /etc/containers/systemd
    ;;
  esphome)
    mkdir -p /etc/opt/esphome/config
    cp esphome/*.yaml /etc/opt/esphome/config
    cp esphome/esphome.container /etc/containers/systemd
    ;;
  home_assistant)
    mkdir -p /etc/opt/home_assistant/certs
    mkdir -p /etc/opt/home_assistant/config
    mkdir -p /var/opt/home_assistant/media/recordings
    cp home_assistant/*.yaml /etc/opt/home_assistant/config
    cp home_assistant/home_assistant.container /etc/containers/systemd
    cp home_assistant/hassdb.volume /etc/containers/systemd
    ;;
  fluentbit)
    mkdir -p /etc/opt/fluentbit
    cp fluentbit/config.yaml.j2 /etc/opt/fluentbit
    cp fluentbit/journald.lua /etc/opt/fluentbit
    /usr/local/bin/render_host.sh homesvcs fluentbit/fluentbit.container
    mv fluentbit/fluentbit.container /etc/containers/systemd
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
