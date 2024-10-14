# Web Services setup
Guide to setup websvcs on PVE2. Just service installation.

- Setup [Podman](./podman.md)

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
src/websvcs/install_svcs.sh homepage
src/websvcs/install_svcs.sh finance_exporter
src/websvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```
