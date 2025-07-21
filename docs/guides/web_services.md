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
src/websvcs/install_svcs.sh isso
# src/websvcs/install_svcs.sh finance_exporter
src/websvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```

## Setup homepage widgets

- Create an API token in the PVE console (for pve1, pve2 and pbs2)
  - Go to Datacenter >> Permissions >> API Tokens >> Add
  - user = api_ro@pam, token ID = homepage
  - Record the secret
```bash
ssh {{ username }}@pve1.{{ site.url }}
sudo /root/homelab-rendered/src/pve1/secret_update.sh websvcs
```
  - Go to Permissions >> Add >> API Token Permission
  - path = /, token = api_ro@..., role = PVEAuditor, propagate = check
  - For PBS, Permissions -> Access Control, PVEAuditor -> Audit
