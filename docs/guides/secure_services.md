# Secure Services setup
Guide to setup secsvcs on PVE1. Includes service installation and network configuration.

- Setup [Podman](./podman.md)

## Setup containers
- Install and start services
```bash
sudo su
cd /root/homelab-rendered
src/secsvcs/install_svcs.sh postgres
src/secsvcs/install_svcs.sh lldap
src/secsvcs/install_svcs.sh authelia
src/secsvcs/install_svcs.sh traefik
src/secsvcs/install_svcs.sh victoriametrics
src/secsvcs/install_svcs.sh victorialogs
src/secsvcs/install_svcs.sh gatus
src/secsvcs/install_svcs.sh alertmanager
src/secsvcs/install_svcs.sh vmalert
src/secsvcs/install_svcs.sh grafana
src/secsvcs/install_svcs.sh ntfy
src/secsvcs/install_svcs.sh ntfy-alertmanager
# src/secsvcs/install_svcs.sh vault
src/secsvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
```

## Networking
- Enable LAN access to postgres, lldap, authelia and ntfy smtp
```bash
NET_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')

ufw allow in from {{ websvcs.ip }} to any port 5432,6360,9091,465 proto tcp
ufw allow in from {{ homesvcs.ip }} to any port 5432,6360,9091,465 proto tcp
ufw route allow in on {{ secsvcs.interface }} out on $NET_IFACE to any port 5432,6360,9091,465 proto tcp
```

- Confirm that the logs for traefik, authelia and lldap look good 
```bash
# Check service status, logs
systemctl status authelia
journalctl -eu authelia
```

- Setup LLDAP
  - In the traefik dynamic config, comment out the authelia middleware from the lldap service (line 33)
    `vim /etc/opt/traefik/config/dynamic/traefik.yml`
  - Navigate to `ldap.{{ site.url }}` and login
    User = admin, get the password below
    `/usr/local/bin/get_secret.sh lldap_admin_password`
  - Add regular users, add them to the `lldap_password_manager` group
    - {% for user in users %}{{ user }}, {% endfor %} (note for future: add_more_users)
  - Create the `authelia_gen_access` and `headscale_access` groups, add users to them
  - Create the `hass_admin` group, add your user to it
  - Uncomment out the authelia middleware
    `vim /etc/opt/traefik/config/dynamic/traefik.yml`

- Confirm that authelia is working, open https://auth.{{ site.url }}

## Ntfy

- Create users, [ref](https://docs.ntfy.sh/config/#users-and-roles)
```bash
chmod 600 /var/opt/ntfy/*.db*
chmod 600 /var/lib/containers/storage/volumes/systemd-ntfydb/_data/*.db*
/usr/local/bin/get_secret.sh ntfy_admin_password
/usr/local/bin/get_secret.sh ntfy_alert_password
/usr/local/bin/get_secret.sh ntfy_hass_password
/usr/local/bin/get_secret.sh ntfy_person_password
podman exec -it ntfy sh
```
```bash
ntfy user add --role=admin admin
ntfy user add alert
ntfy access alert "alert*" rw
ntfy access alert "comment*" rw
ntfy user add hass
ntfy access hass "hass*" rw
ntfy user add person
ntfy access person "hass*" ro
ntfy access person "chat*" rw
# save for later
ntfy token add alert
exit
```
- Record access token as a secret on pve1
```bash
ssh admin@pve1.{{ site.url }}
sudo su
/root/homelab-rendered/src/pve1/secret_update.sh secsvcs
/root/homelab-rendered/src/pve1/secret_update.sh websvcs
exit
exit
```

## Debugging (optional)
- Find container image name
  - `podman search traefik --limit 10`

- Check unit generation
```bash
/usr/lib/systemd/system-generators/podman-system-generator -v --dryrun

/usr/lib/systemd/system-generators/podman-system-generator
ls /run/systemd/generator/
```

- Confirm generator ran successfully
  - `journalctl -e`

- List services and status
```
systemctl list-unit-files
systemctl --type=service
```

## Upgrade Postgres
[Why upgrade](https://why-upgrade.depesz.com/)

- Backup the DB instance
```bash
sudo su
cd /root/backups
systemctl list-units | grep Homelab
# Stop all other homelab services in reserve order of installation
systemctl stop ALL_OTHER_SERVICES
podman container ls | grep postgres
podman exec -it --user 70 CONTAINER_ID pg_dumpall -U postgres > pgdump-$(date -I).sql
systemctl stop postgres
```
- Upgrade and restore from backup
```bash
cd /root/backups
podman container ls | grep postgres
src/secsvcs/install_svcs.sh postgres
podman exec -it --user 70 CONTAINER_ID psql -U postgres < FILE.sql
systemctl start ALL_OTHER_SERVICES
```

## Backup Victoriametrics
[Ref](https://docs.victoriametrics.com/vmbackup/)

- Backup
  - TODO: fix the 401 returned by VM
```bash
sudo su
mkdir /root/backups/metrics
podman run --replace -it --name=vmbackup \
  --network=systemd-net -v /root/backups/metrics:/backup -v systemd-vmdata:/data \
  --secret victoriametrics_admin_password,type=env,target=httpAuth_password \
  docker.io/victoriametrics/vmbackup:latest \
  -envflag.enable -httpAuth.username="admin" -storageDataPath=/data -snapshot.createURL=http://metrics.{{ site.url }}:8428/snapshot/create -dst=fs:///backup
```

- Restore
```bash
systemctl stop victoriametrics
podman run --replace -it --name=vmrestore \
  -v /root/backups/metrics:/backup -v systemd-vmdata:/data \
  docker.io/victoriametrics/vmrestore:latest \
  -storageDataPath=/data -src=fs:///backup
systemctl start victoriametrics
```
