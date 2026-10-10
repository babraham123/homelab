#!/bin/bash
# Installs homesvcs specific systemd services.
# Usage:
#   src/homesvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic homesvcs/traefik/*.yml traefik/dynamic/*.yml
    install -D -m 644 traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    install -D -m 644 -t /etc/containers/systemd homesvcs/traefik/traefik.container
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent homesvcs/prometheus.yml
    /root/homelab-rendered/src/podman/render_host.sh homesvcs victoriametrics/vmagent.container
    install -D -m 644 -t /etc/containers/systemd victoriametrics/vmagent.container victoriametrics/vmagentdata.volume
    ;;
  mosquitto)
    mkdir -p /etc/opt/mosquitto/certificates
    install -D -m 644 -t /etc/opt/mosquitto mosquitto/mosquitto.conf
    install -D -m 644 -t /etc/containers/systemd mosquitto/mosquitto.container mosquitto/mqttdata.volume
    ;;
  zigbee2mqtt)
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    install -D -m 644 -t /etc/opt/zigbee2mqtt/config zigbee2mqtt/*.yaml
    install -D -m 644 -t /etc/containers/systemd zigbee2mqtt/zigbee2mqtt.container zigbee2mqtt/z2mdb.volume
    ;;
  esphome)
    install -D -m 644 -t /etc/opt/esphome/config esphome/*.yaml
    install -D -m 644 -t /etc/containers/systemd esphome/esphome.container
    ;;
  home_assistant)
    mkdir -p /etc/opt/home_assistant/certs
    mkdir -p /var/opt/home_assistant/media/recordings
    install -D -m 644 -t /etc/containers/systemd home_assistant/hassconfig.volume
    systemctl daemon-reload
    systemctl start hassconfig-volume.service
    volpath=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-hassconfig)
    if [ ! -e "$volpath"/configuration.yaml ]; then
      install -m 644 -t "$volpath" home_assistant/*.yaml
    else
      echo "$volpath"
      ls "$volpath"
      echo -n "Have you manually updated the config files? Y or N: "
      read -r reply
      if [[ ! $reply =~ ^[Yy]$ ]]; then
        exit 1
      fi
    fi
    install -D -m 644 -t /etc/containers/systemd home_assistant/home_assistant.container home_assistant/hassdb.volume
    ;;
  fluentbit)
    install -D -m 644 fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit fluentbit/journald.lua
    install -D -m 644 debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    /root/homelab-rendered/src/podman/render_host.sh homesvcs fluentbit/fluentbit.container
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
