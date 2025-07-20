# Home Assistant setup
Guide to setup Home Assistant and related services on PVE1.

- Setup [Podman](./podman.md)

## Setup containers
- Install and start services
```bash
sudo su
cd /root/homelab-rendered
src/homesvcs/install_svcs.sh traefik
src/homesvcs/install_svcs.sh vmagent
src/debian/install_svcs.sh mdns_repeater
src/homesvcs/install_svcs.sh mosquitto
src/homesvcs/install_svcs.sh zigbee2mqtt
# src/homesvcs/install_svcs.sh esphome
src/homesvcs/install_svcs.sh home_assistant
src/homesvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```

- On initial install, disable HA OIDC, watchdog
```bash
# Comment out the sections called `auth_oidc` and `binary_sensor`
vim /etc/opt/home_assistant/config/configuration.yaml
# Comment out `notify` and `WatchdogSec`
vim /etc/containers/systemd/home_assistant.container

systemctl daemon-reload
systemctl restart home_assistant
```

## Networking
Refs: [ESPHome](https://esphome.io/components/ota/esphome.html), [Shelly](https://www.home-assistant.io/integrations/shelly)
- Enable LAN access to various services
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

## Onboarding

[Ref](https://www.home-assistant.io/getting-started/onboarding/)
- Create an `admin` account
- Go thru the setup wizard
- Go to Admin >> enable Advanced Mode
- Go to Settings >> Areas, ... >> create any missing areas
- Install HACS
  - Run the installer script
```bash
podman container ls | grep home_assistant
podman exec -it CONTAINER_ID bash

# In the new shell
wget -O - https://get.hacs.xyz | bash -
exit

systemctl restart home_assistant
```
  - Go to Settings >> Devices & services
  - Reload the page. Search and install `HACS`
  - Perform device auth with Github
  - Go to Settings >> Devices & services >> Gear icon >> Enable AppDaemon apps
- Go to HACS >> install the following integrations:
  - brianegge/home-assistant-sdnotify
  - christiaangoossens/hass-oidc-auth
  - dummylabs/thewatchman
- Configure the integrations
```bash
# Uncomment the sections called `auth_oidc` and `binary_sensor`
vim /etc/opt/home_assistant/config/configuration.yaml
# Uncomment `notify` and `WatchdogSec`
vim /etc/containers/systemd/home_assistant.container

systemctl daemon-reload
systemctl restart home_assistant
```
