# Home Assistant setup
Guide to setup Home Assistant and related services on PVE1.

- Setup [Podman](./podman.md)

## Setup containers
- Install and start services
```bash
- Install and start containers
```bash
sudo su
cd /root/homelab-rendered
src/homesvcs/install_svcs.sh traefik
src/homesvcs/install_svcs.sh vmagent
src/homesvcs/install_svcs.sh mosquitto
src/homesvcs/install_svcs.sh zigbee2mqtt
src/homesvcs/install_svcs.sh esphome
src/homesvcs/install_svcs.sh home_assistant
src/homesvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```

## Networking
Refs: [ESPHome](https://esphome.io/components/ota/esphome.html), [Shelly](https://www.home-assistant.io/integrations/shelly)
- Enable LAN access to various services.
```bash
NET_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
# TODO: For iot devices, migrate from LAN to wifi vlan
# MQTT broker
ufw allow in from any to any port 1883 proto tcp
ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 1883
# ESPHome OTA updates
ufw allow in from {{ lan.mask }} to any port 3232,8266,2040,8892 proto tcp
ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 3232,8266,2040,8892 proto tcp
# HA, Shelly devices
# ufw allow in from {{ lan.mask }} to any port 5683 proto udp
# ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 5683
```
