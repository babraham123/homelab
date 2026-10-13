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
- Install and start services. Each install loads its images through the [image
  updater](./podman.md#image-updater) first, which stops on a blocked image
```bash
sudo su
cd /root/homelab-rendered
# Traefik needs crowdsec_bouncer_homesvcs in its secrets, and the WAF its client certificate
# (secsvcs guide: Traefik bouncer and WAF)
src/nodes/homesvcs/install_svcs.sh traefik
src/nodes/homesvcs/install_svcs.sh crowdsec_appsec
src/nodes/homesvcs/install_svcs.sh vmagent
src/nodes/homesvcs/install_svcs.sh mosquitto
src/nodes/homesvcs/install_svcs.sh zigbee2mqtt
# src/nodes/homesvcs/install_svcs.sh esphome
src/nodes/homesvcs/install_svcs.sh home_assistant
src/nodes/homesvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
systemctl restart mdns_repeater
systemctl list-units | grep Homelab
# Every image unchanged: the installs just loaded them
src/base/podman/image_updater.sh --dry-run
```

- On initial install, disable HA OIDC
```bash
# Comment out the sections called `auth_oidc`
volpath=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-hassconfig)
vim $volpath/configuration.yaml
systemctl restart home_assistant
```

## Networking
Refs: [ESPHome](https://esphome.io/components/ota/esphome.html),
[Shelly](https://www.home-assistant.io/integrations/shelly)
- Enable LAN access to various services
```bash
POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')
# MQTT broker
ufw allow in from any to any port 8883 proto tcp
ufw route allow in on $NET_IFACE out on $POD_IFACE to any port 8883 proto tcp
# ESPHome OTA updates. Published ports are DNATed to the containers, so the route rules are
# what admit the traffic
ufw allow in from 192.168.11.0/24 to any port 3232,8266,2040,8892 proto tcp
ufw allow in from 192.168.21.0/24 to any port 3232,8266,2040,8892 proto tcp
ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.11.0/24 to any port 3232,8266,2040,8892 proto tcp
ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.21.0/24 to any port 3232,8266,2040,8892 proto tcp
# HA, Shelly devices
# ufw allow in from 192.168.11.0/24 to any port 5683 proto udp
# ufw allow in from 192.168.21.0/24 to any port 5683 proto udp
# ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.11.0/24 to any port 5683 proto udp
# ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.21.0/24 to any port 5683 proto udp
```

## Onboarding
[Ref](https://www.home-assistant.io/getting-started/onboarding/)

- Create an `admin` account
- Go thru the setup wizard
- Go to Admin >> enable Advanced Mode
- Setup areas
  - Go to Settings >> Areas, ... >> create any missing areas
- Connect to MQTT broker
  - Go to Settings >> Devices & Services >> Add Integration
  - Search MQTT and add
  - Set the broker hostname (mqtt.janedoe.com) and port (8883). Press Submit
  - Enable "Use a client certificate", set Broker cert validation to "Auto". Press Submit
  - From personal computer, copy out the client cert and key installed under
    `/etc/opt/home_assistant/certs`
    ```bash
    ssh -t manualadmin@homesvcs 'sudo install -m 600 -o manualadmin /etc/opt/home_assistant/certs/client.pem /etc/opt/home_assistant/certs/client.key ~'
    scp 'manualadmin@homesvcs:client.*' ~/Downloads
    ssh manualadmin@homesvcs 'rm ~/client.pem ~/client.key'
    ```
  - Upload the client cert and key. Press Submit
- Connect to InfluxDB
  - Go to Settings >> Devices & Services >> Add Integration
  - Search InfluxDB and add
  - version = 2.x/3, url = https://metrics.janedoe.com:443/api/v2/write, verify SSL,
    organization = hass, bucket = hass
  - To get the token, run
    `/root/homelab-rendered/src/base/podman/get_secret.sh victoriametrics_admin_creds_hash`
- Create the backup token
  - As the `admin` user, go to Profile >> Security >> Long-lived access tokens >> Create token
  - Store it as `hass_backup_token` in the homesvcs secrets
```bash
ssh -t manualadmin@pve1 'sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh homesvcs'
```
- Install HACS
  - Run the installer script
    ```bash
    container=$(podman container ls | grep home_assistant | awk '{print $1}')
    podman exec -it "$container" bash

    # In the new shell
    wget -O - https://get.hacs.xyz | bash -
    exit

    systemctl restart home_assistant
    ```
  - Go to Settings >> Devices & services
  - Reload the page. Click `Add Integration`. Search and install `HACS`
  - Perform device auth with Github
  - Go to Gear icon >> Enable AppDaemon apps
- Go to HACS >> install the following integrations:
  - christiaangoossens/hass-oidc-auth
  - dummylabs/thewatchman
- Restart and add OIDC
```bash
# Uncomment the sections called `auth_oidc`
vim $volpath/configuration.yaml
systemctl restart home_assistant
```
- Add Watchman
  - Go to Settings >> Devices & services >> Add Integration
  - Search Watchman and add
- Generate a configuration report
  - Go to Settings >> Developer Tools >> Actions
  - Search Watchman and press `Perform Action`

## Devices
IoT devices sit on their own VLAN, see [Networking](../networking.md#vlans) and [mDNS across
VLANs](../networking.md#mdns-across-vlans). The Zigbee coordinator and other peripherals are listed
under [network gear](../architecture.md#network-gear-and-peripherals).
