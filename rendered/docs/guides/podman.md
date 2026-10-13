# Podman setup
Initial setup to install Podman on a Debian VM or the VPS and configure it with the relevant scripts
and services.

- Setup [Debian Linux](./debian.md)
- Make sure to do VM Host setup for [PVE1](./pve1.md) and [PVE2](./pve2.md).
- Review container security measures, for example
  [ref](https://www.panoptica.app/research/7-ways-to-escape-a-container)

## Install Podman
- Install dependencies
```bash
sudo su
apt install -y age jq gnupg2 zstd
/root/homelab-rendered/src/base/debian/install_render_tools.sh
```

- Install podman: [ref](https://podman.io/docs/installation#linux-distributions),
  [ref2](https://computingforgeeks.com/how-to-install-podman-on-debian/)
```bash
/root/homelab-rendered/src/base/podman/install_podman.sh
```

## Networking
- Account for conflicts between the podman network and the firewall,
  [bug](https://stackoverflow.com/questions/70870689/configure-ufw-for-podman-on-port-443)
- Create the container network. On the VMs this also resets the firewall and lets Traefik's
  traffic through to its container; vpnsvcs keeps the rules from [its
  guide](./vpnsvcs.md#add-public-endpoint) and publishes nothing.
```bash
/root/homelab-rendered/src/base/podman/install_network.sh
```

## Secrets
- On the VM host, update the SOPS/AGE secrets file if needed
- Configure secrets
```bash
sudo su
# Read secrets from age-encrypted file
mkdir -p /etc/opt/secrets
chmod 700 /etc/opt/secrets
cp /home/manualadmin/.ssh/id_ed25519* /etc/opt/secrets
chmod 600 /etc/opt/secrets/*
cp /root/homelab-rendered/src/base/podman/containers.conf /etc/containers
```
The secret helpers (`src/base/podman/*.sh`) run in place from `/root/homelab-rendered`; nothing is
copied, so a deploy updates them.

## mDNS
- Install dependencies and service
```bash
/root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
```

## Monitoring
- Install Node Exporter
```bash
adduser node_exporter --system
groupadd node_exporter
usermod -a -G node_exporter node_exporter
cd /root/homelab-rendered
src/base/debian/install_svcs.sh node_exporter
```

- Allow access from metrics container to host in order to scrape node_exporter
```bash
# Use 10.10.0.7 on secsvcs, 10.11.0.7 on websvcs, 10.12.0.7 on homesvcs,
# 10.13.0.7 on vpnsvcs
ufw allow in from 10.10.0.7 to any port 9100 proto tcp
```

## Image updater
Quadlets only run `localhost/` images. The image updater downloads (or builds) each one, scans it
with Trivy and loads it, when a service is installed and every night after: see
[Maintenance](../maintenance.md#container-images).
- The node's secrets file needs `docker_hub_username`, `docker_hub_token` and `ntfy_alert_token`
- Install it before any service, since every `install_svcs.sh` case scans its images through it
```bash
cd /root/homelab-rendered
src/base/debian/install_svcs.sh image_updater
systemctl enable --now image_updater.timer
systemctl list-timers image_updater.timer
```

## Backups
The scheduled backup is each node's `backup.sh`, see [Services](../services.md#storage-and-backups).
What follows is the manual fallback for a volume it doesn't cover.

- Backup container volumes
```bash
cd /root/backups
systemctl list-units | grep Homelab
# Stop all homelab services in reserve order of installation
systemctl stop ALL_SERVICES
# Archive the relevant volumes
now=$(date -I)
podman volume ls --format json | jq -r '.[].Name' | \
  xargs -I% podman volume export % -o %-$now.tar
gzip *.tar
# Restart all homelab services in order of installation
systemctl start ALL_SERVICES
```

- Restore a container volume
```bash
cd /root/backups
systemctl stop ALL_SERVICES
gunzip FILE.tar.gz
podman volume import VOLUME FILE.tar
systemctl start ALL_SERVICES
```

- Backup a container image
```bash
cd /root/backups
podman images --format=json | \
  jq -r '.[].Names.[0]' | tr '/' '#' | \
  xargs -I% podman save -o %.tar %
gzip *.tar

gunzip FILE.tar.gz
podman load -i IMAGE-NAME.tar
```
