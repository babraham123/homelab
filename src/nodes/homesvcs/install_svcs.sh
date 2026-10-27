#!/bin/bash
# Installs homesvcs specific systemd services.
# Usage:
#   src/nodes/homesvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cd "$rendered"
watch_homelab_units

# Every image the case's quadlets name is downloaded (or built) and passes the scan gate
# before any quadlet is copied; a blocked image stops the install here.
/usr/local/bin/image_updater install "${1:?usage: $0 SERVICE_NAME}"

# Usage: sync_dir SRC DEST; DEST's contents become SRC's. Replaced in place, since a
# container's bind mount holds on to the directory itself, not its path.
sync_dir() {
  find "$2" -mindepth 1 -delete
  cp -R "$1/." "$2"
}

case $1 in
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
    config=/etc/opt/home_assistant/config
    installed=/etc/opt/home_assistant/config.installed
    mkdir -p /etc/opt/home_assistant/certs "$config"
    mkdir -p /var/opt/home_assistant/media/recordings
    # The container mounts $config writable, so changes can be tried live; $installed is
    # what the last install put there, and edits since only survive by going through git
    if [[ -e "$installed" ]] && ! diff -ru "$installed" "$config"; then
      die "home_assistant: $config was edited since the last install (diff above). Port the" \
        "edits to src/services/home_assistant/config, or discard them: rm -r $installed"
    fi
    install_quadlet services/home_assistant/hassconfig.volume
    systemctl daemon-reload
    systemctl start hassconfig-volume.service
    volpath=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-hassconfig)
    # Links resolved inside the container, where $config is /config/homelab. A regular
    # file in their place may be the only copy of edits made before the split.
    for name in configuration.yaml custom_sentences; do
      if [[ -e "$volpath/$name" && ! -L "$volpath/$name" ]]; then
        die "home_assistant: $volpath/$name predates the homelab/ mount. Port its edits to" \
          "src/services/home_assistant/config, then remove it"
      fi
      ln -sfn "homelab/$name" "$volpath/$name"
    done
    # The UI editors' files, never overwritten
    for name in automations scripts scenes; do touch "$volpath/$name.yaml"; done
    prev=$(mktemp -d)
    cp -R "$config/." "$prev"
    sync_dir services/home_assistant/config "$config"
    # A running container that mounts $config already sees the new files, along with its
    # secrets and custom integrations, so they're checked before the restart loads them
    if podman exec home_assistant test -e /config/homelab/configuration.yaml 2> /dev/null &&
      ! podman exec home_assistant python -m homeassistant --script check_config --config /config; then
      sync_dir "$prev" "$config"
      die "home_assistant: config check failed (above); the previous config is back in place"
    fi
    rm -rf "$prev" "$installed"
    cp -R "$config" "$installed"
    install_quadlet services/home_assistant/home_assistant.container services/home_assistant/hassdb.volume
    reload_restart home_assistant
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
