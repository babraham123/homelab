# Web Services setup

- Setup Podman using [podman_setup.md](./podman_setup.md)

## Setup containers
- Install and start services
```bash
- Install and start containers
```bash
sudo su
cd /root/homelab-rendered
src/websvcs/install_svcs.sh traefik
src/websvcs/install_svcs.sh vmagent
src/websvcs/install_svcs.sh nginx
src/websvcs/install_svcs.sh dashy
src/websvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```
