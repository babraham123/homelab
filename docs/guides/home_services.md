# Home Assistant setup
Guide to setup Home Assistant and related services on PVE1.

- Setup [Podman](./podman.md)

## Zigbee Adapter
I use the SMLight SLZB-06M adapter, it's reasonably priced and very feature rich.

- [Configuration and guide](https://smlight.tech/manual/slzb-06/guide/configuration/)
- Flash firmware OTA
  - Go to http://slzb-06m.local >> Settings and Tools >> Firmware update
  - Flash the SLZB OS and the Zigbee Coordinator images
- [Flash over USB](https://smlight.tech/flasher/#home) if you get locked out

## Setup containers
- Install and start services
```bash
sudo su
cd /root/homelab-rendered
src/homesvcs/install_svcs.sh traefik
src/homesvcs/install_svcs.sh vmagent
src/homesvcs/install_svcs.sh mosquitto
src/homesvcs/install_svcs.sh zigbee2mqtt
# src/homesvcs/install_svcs.sh esphome
src/homesvcs/install_svcs.sh home_assistant
src/homesvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```

- On initial install, disable HA OIDC
```bash
# Comment out the sections called `auth_oidc`
vim /etc/opt/home_assistant/config/configuration.yaml
systemctl restart home_assistant
```

## Networking
Refs: [ESPHome](https://esphome.io/components/ota/esphome.html), [Shelly](https://www.home-assistant.io/integrations/shelly)
- Enable LAN access to various services
```bash
NET_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
# MQTT broker
ufw allow in from any to any port 8883 proto tcp
ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 8883
# ESPHome OTA updates
ufw allow in from {{ wifi.iot.mask }} to any port 3232,8266,2040,8892 proto tcp
ufw allow in from {{ wired.iot.mask }} to any port 3232,8266,2040,8892 proto tcp
ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 3232,8266,2040,8892 proto tcp
# HA, Shelly devices
# ufw allow in from {{ wifi.iot.mask }} to any port 5683 proto udp
# ufw allow in from {{ wired.iot.mask }} to any port 5683 proto udp
# ufw route allow in on {{ homesvcs.interface }} out on $NET_IFACE to any port 5683
```

## Onboarding
[Ref](https://www.home-assistant.io/getting-started/onboarding/)

- Create an `admin` account
- Go thru the setup wizard
- Go to Admin >> enable Advanced Mode
- Setup areas
  - Go to Settings >> Areas, ... >> create any missing areas
- Connect to MQTT broker
  - Go to Settings >> Devices & Services
  - TODO: !!
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
  - christiaangoossens/hass-oidc-auth
  - dummylabs/thewatchman
- Configure the integrations
```bash
# Uncomment the sections called `auth_oidc`
vim /etc/opt/home_assistant/config/configuration.yaml
systemctl restart home_assistant
```

## Devices
Check out the [IoT guide](./iot_devices.md) for device specific info.
