# Secure Services setup

Guide to setup secsvcs on PVE1. Includes service installation and network configuration.

- Setup [Podman](./podman.md)

## Setup containers

- Install and start services. Each install loads its images through the
  [image updater](./podman.md#image-updater)

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
# needs the prerequisites in Vaultwarden below
src/nodes/secsvcs/install_svcs.sh vaultwarden
src/nodes/secsvcs/install_svcs.sh olive_tin
# needs the prerequisites in CrowdSec below
src/nodes/secsvcs/install_svcs.sh crowdsec
src/nodes/secsvcs/install_svcs.sh crowdsec_appsec
src/nodes/secsvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
systemctl restart mdns_repeater
systemctl list-units | grep Homelab
# Expect every image unchanged
src/base/podman/image_updater.py --dry-run
```

## Networking

- Enable LAN access to postgres, lldap, authelia and ntfy smtp

```bash
POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')

ufw allow in from 192.168.4.21 to any port 5432,6360,9091,465 proto tcp
ufw allow in from 192.168.2.20 to any port 5432,6360,9091,465 proto tcp
# Published ports are DNATed, so the route rules admit the traffic
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
  - Remove authelia from the lldap router: `middlewares: [secure-headers@file]`
    - `vim /etc/opt/traefik/config/dynamic/routes.yml`
  - Navigate to `ldap.janedoe.com` and login User = admin, get the password below
    `/root/homelab-rendered/src/base/podman/get_secret.sh lldap_admin_password`
  - Add regular users, not in `lldap_password_manager` (it can reset others' passwords)
    - jane
    - jane, jayden, jasper
  - Create the `authelia_gen_access`, `headscale_access`, `command_general` and
    `vaultwarden_access` groups, add users to them
  - Create the `telemetry` group (metrics, logs and alert UIs), add your user to it
  - Create the `grafana_admin`, `hass_admin`, `command_admin` and `files_admin` groups, add your
    user to them
  - Restore the authelia middleware
    `/root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik`

- Confirm that authelia is working, open <https://auth.janedoe.com>

## CrowdSec

[ADR 0009](../adr/0009-crowdsec-lapi-on-secsvcs.md), [VPS bouncer](./vpnsvcs.md#crowdsec-bouncer)

- Prerequisites, on pve1:
  - Run `self_signed_key_gen.sh` and `self_signed_cert_gen.sh` for the `crowdsec.janedoe.com`
    key and cert, then restart the secure services
  - Add `crowdsec_bouncer_vpnsvcs` to `/root/secrets/secsvcs.yaml`, then
    `sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs`
- Admit the VPS (from its tailnet IP) and the other Traefiks to the LAPI port

```bash
sudo su
cd /root/homelab-rendered
POD_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')
for src in 100.64.0.2 192.168.4.21 192.168.2.20; do
  ufw allow in from $src to any port 8455 proto tcp
  ufw route allow in on $NET_IFACE out on $POD_IFACE from $src to any port 8455 proto tcp
done
```

- Install and check

```bash
src/nodes/secsvcs/install_svcs.sh crowdsec
podman exec crowdsec cscli lapi status
podman exec crowdsec cscli capi status          # registered, blocklist pulled
podman exec crowdsec cscli metrics show acquisition parsers   # traefik and authelia lines parsed
src/nodes/secsvcs/install_svcs.sh fluentbit     # ship the new unit's journal
```

- New online API identity: delete `/etc/opt/crowdsec/config/online_api_credentials.yaml` and the
  `online_client` block in `config.yaml`, then restart
- Day to day

```bash
podman exec crowdsec cscli decisions list             # local bans; add -a for the blocklist
podman exec crowdsec cscli alerts list
podman exec crowdsec cscli decisions delete --ip IP   # unban
```

- Test from an outside IP (a phone off Wi-Fi): expect a ban in `cscli decisions list` and
  `nft list ruleset` on the VPS, and `:443` timing out

```bash
for i in $(seq 40); do curl -s -o /dev/null https://www.janedoe.com/nope$i; done
```

- Test `auth.janedoe.com`: six failed logins from outside with different usernames, expect a ban
- Check that LAN, tailnet and VPS addresses never appear in `cscli decisions list`
- Monitor: Grafana "CrowdSec" dashboard, alerts in `src/services/vmalert/configs/crowdsec.yml`

### Traefik WAF

[Security](../security.md#the-edge-haproxy). Follow this order: an unknown key gets a 403 on every
request.

1. On pve1: add `crowdsec_bouncer_secsvcs`, `crowdsec_bouncer_homesvcs` and
   `crowdsec_bouncer_websvcs` to `/root/secrets/secsvcs.yaml` and each node's secrets file. Run
   `self_signed_key_gen.sh` and `self_signed_cert_gen.sh` for the `appsec-<node>` certs

   ```bash
   for node in secsvcs homesvcs websvcs; do
     sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh $node
   done
   ```

2. On secsvcs

   ```bash
   src/nodes/secsvcs/install_svcs.sh crowdsec
   podman exec crowdsec cscli bouncers list    # vpnsvcs, and traefik_<node> for all three
   src/nodes/secsvcs/install_svcs.sh crowdsec_appsec
   src/nodes/secsvcs/install_svcs.sh traefik
   ```

3. On homesvcs and websvcs: `install_svcs.sh crowdsec_appsec`, then `install_svcs.sh traefik`
4. Check, on secsvcs

   ```bash
   podman exec crowdsec cscli machines list   # appsec-<node>@<IP>, validated, for all three
   podman exec crowdsec cscli bouncers list   # each traefik_<node> seen after the first request
   podman exec crowdsec_appsec cscli metrics show appsec   # requests processed
   journalctl -u traefik | grep -i crowdsec   # no plugin errors
   ```

- Test from an outside IP: expect a 403 and an alert in `cscli alerts list`. From the LAN: blocked,
  never banned

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'https://www.janedoe.com/?q=<script>alert(1)</script>'
```

- The Core Rule Set only alerts (scenarios `anomaly score*`). Add exclusions for false positives,
  then move it in-band

## Vaultwarden

<https://vault.janedoe.com>: SSO-only, gated on the `vaultwarden_access` LLDAP group

- Prerequisites:
  - On pve1, add `vaultwarden_*` to `/root/secrets/secsvcs.yaml` (recipes in the template), then
    `sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs`
  - Keep the plaintext admin token in the escrow bundle; SOPS holds only its hash
  - Set your LLDAP email to `jdoe@gmail.com` (`ORG_CREATION_USERS`)
- Install. On an existing Postgres cluster, create the database by hand once

```bash
sudo su
cd /root/homelab-rendered
src/nodes/secsvcs/install_svcs.sh postgres
src/nodes/secsvcs/install_svcs.sh authelia
sed -n '/Vaultwarden DB/,/CREATE DATABASE vaultwarden/p' /var/opt/db/pg_init.sql \
  | podman exec -i postgres psql -U postgres -v ON_ERROR_STOP=1
src/nodes/secsvcs/install_svcs.sh vaultwarden
src/nodes/secsvcs/install_svcs.sh traefik
curl -fsS https://vault.janedoe.com/alive
```

- First login: "Use single sign-on" (any organization identifier), Authelia two-factor and consent,
  then set the master password (12+ characters)
- Add a user to an organization only after they've signed in once
- Treat `/admin` as read-only: change settings in `src/services/vaultwarden/vaultwarden.container.j2`,
  since saving in `/admin` writes `/data/config.json`, which overrides it
- Linux desktop app: needs a `bitwarden://` protocol handler in the browser
- Phones sync when opened or on pull-to-refresh (no push relay)
- Failed admin logins: `journalctl -u vaultwarden | grep "Invalid admin token"`
- Keep a password-protected JSON export (Tools >> Export vault, `.json (Password protected)`) in the
  escrow bundle

## Ntfy

- Users, access and tokens come from the config file,
  [ref](https://docs.ntfy.sh/config/#users-via-the-config)
- Lock down the databases. Remove any user or token not marked `server config`

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

```bash
systemctl list-unit-files
systemctl --type=service
```

## Upgrade Postgres

[Why upgrade](https://why-upgrade.depesz.com/)

- From 14: hand each database to its app's role first, so the dump carries the owners

```bash
for db in lldap authelia gatus grafana guacamole; do
  podman exec postgres psql -U postgres -c "ALTER DATABASE $db OWNER TO $db"
done
```

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
