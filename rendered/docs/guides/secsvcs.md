# Secure Services setup
Guide to setup secsvcs on PVE1. Includes service installation and network configuration.

- Setup [Podman](./podman.md)

## Setup containers
- Install and start services. Each install loads its images through the [image
  updater](./podman.md#image-updater) first, which stops on a blocked image
```bash
sudo su
cd /root/homelab-rendered
src/nodes/secsvcs/install_svcs.sh postgres
src/nodes/secsvcs/install_svcs.sh lldap
src/nodes/secsvcs/install_svcs.sh authelia
src/nodes/secsvcs/install_svcs.sh traefik
src/nodes/secsvcs/install_svcs.sh victoriametrics
src/nodes/secsvcs/install_svcs.sh victorialogs
src/nodes/secsvcs/install_svcs.sh gatus
src/nodes/secsvcs/install_svcs.sh alertmanager
src/nodes/secsvcs/install_svcs.sh vmalert
src/nodes/secsvcs/install_svcs.sh grafana
src/nodes/secsvcs/install_svcs.sh ntfy
src/nodes/secsvcs/install_svcs.sh ntfy-alertmanager
# src/nodes/secsvcs/install_svcs.sh vault
src/nodes/secsvcs/install_svcs.sh olive_tin
src/nodes/secsvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
systemctl restart mdns_repeater
systemctl list-units | grep Homelab
# Every image unchanged: the installs just loaded them
src/base/podman/image_updater.sh --dry-run
```

## Networking
- Enable LAN access to postgres, lldap, authelia and ntfy smtp
```bash
POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')

ufw allow in from 192.168.4.21 to any port 5432,6360,9091,465 proto tcp
ufw allow in from 192.168.2.20 to any port 5432,6360,9091,465 proto tcp
# Published ports are DNATed to the containers, so these route rules are what admit the traffic
ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.4.21 to any port 5432,6360,9091,465 proto tcp
ufw route allow in on $NET_IFACE out on $POD_IFACE from 192.168.2.20 to any port 5432,6360,9091,465 proto tcp
```

- Confirm that the logs for traefik, authelia and lldap look good
```bash
# Check service status, logs
systemctl status authelia
journalctl -eu authelia
```

- Setup LLDAP
  - In the traefik dynamic config, give the lldap router its own middlewares without authelia:
    `middlewares: [secure-headers@file]` `vim /etc/opt/traefik/config/dynamic/routes.yml`
  - Navigate to `ldap.janedoe.com` and login User = admin, get the password below
    `/root/homelab-rendered/src/base/podman/get_secret.sh lldap_admin_password`
  - Add regular users, add them to the `lldap_password_manager` group, (note for future:
    add_more_users)
    - jane
    - jane, jayden, jasper, 
  - Create the `authelia_gen_access`, `headscale_access` and `command_general` groups, add users to
    them
  - Create the `grafana_admin`, `hass_admin` and `command_admin` groups, add your user to it
  - Restore the authelia middleware by reinstalling the traefik config
    `/root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik`

- Confirm that authelia is working, open https://auth.janedoe.com

## Ntfy

- Users, access control and tokens are provisioned from the config file (`auth-users`,
  `auth-access`, `auth-tokens`), [ref](https://docs.ntfy.sh/config/#users-via-the-config)
  - Existing users and tokens with the same name/value (e.g. created via the CLI) are adopted on
    restart. Any entry not tagged `server config` below is a leftover and should be removed.
- Lock down the databases and confirm the users are marked `server config`
```bash
chmod 600 /var/opt/ntfy/*.db*
chmod 600 /var/lib/containers/storage/volumes/systemd-ntfydb/_data/*.db*
podman exec ntfy ntfy access
podman exec ntfy ntfy token list
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
container=$(podman container ls | grep postgres | awk '{print $1}')
now=$(date -I)
podman exec -it --user 70 "$container" pg_dumpall -U postgres --clean --if-exists > pgdump-$now.sql
gzip *.sql
systemctl stop postgres
```
- Upgrade and restore from backup
```bash
cd /root/backups
/root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh postgres
gunzip FILE.sql.gz
container=$(podman container ls | grep postgres | awk '{print $1}')
podman exec -it --user 70 "$container" psql -U postgres < FILE.sql
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
  -envflag.enable -httpAuth.username="admin" -storageDataPath=/data -snapshot.createURL=http://metrics.janedoe.com:8428/snapshot/create -dst=fs:///backup
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
