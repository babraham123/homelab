#!/bin/bash
# Installs homesvcs specific systemd services.
# Usage:
#   src/nodes/homesvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/svcs_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/svcs_lib.sh"

cd "$rendered"

# Every image the case's quadlets name is downloaded (or built) and passes the scan gate
# before any quadlet is copied; a blocked image stops the install here.
base/podman/image_updater.sh install "${1:?usage: $0 SERVICE_NAME}"

case $1 in
  traefik)
    install_traefik_config homesvcs
    install_quadlet nodes/homesvcs/traefik/traefik.container
    reload_restart traefik
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent nodes/homesvcs/prometheus.yml
    base/podman/render_host.sh homesvcs services/victoriametrics/vmagent.container
    install_quadlet services/victoriametrics/vmagent.container services/victoriametrics/vmagentdata.volume
    reload_restart vmagent
    ;;
  mosquitto)
    mkdir -p /etc/opt/mosquitto/certificates
    install -D -m 644 -t /etc/opt/mosquitto services/mosquitto/mosquitto.conf
    install_quadlet services/mosquitto/mosquitto.container services/mosquitto/mqttdata.volume
    reload_restart mosquitto
    ;;
  zigbee2mqtt)
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    install -D -m 644 -t /etc/opt/zigbee2mqtt/config services/zigbee2mqtt/*.yaml
    install_quadlet services/zigbee2mqtt/zigbee2mqtt.container services/zigbee2mqtt/z2mdb.volume
    reload_restart zigbee2mqtt
    ;;
  # Not in use: uncomment and add to src/nodes/homesvcs/inventory.yml to install again
#   esphome)
#     install -D -m 644 -t /etc/opt/esphome/config services/esphome/*.yaml
#     install_quadlet services/esphome/esphome.container
#     reload_restart esphome
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
    reload_restart home_assistant
    ;;
  fluentbit)
    install_fluentbit_config
    base/podman/render_host.sh homesvcs services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    reload_restart fluentbit
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
