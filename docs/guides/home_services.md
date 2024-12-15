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
src/homesvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```
