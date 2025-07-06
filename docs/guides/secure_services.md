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
- Enable LAN access to postgres, lldap and authelia
```bash
NET_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')

ufw allow in from {{ websvcs.ip }} to any port 5432,6360,9091 proto tcp
ufw allow in from {{ homesvcs.ip }} to any port 5432,6360,9091 proto tcp
ufw route allow in on {{ secsvcs.interface }} out on $NET_IFACE to any port 5432,6360,9091 proto tcp
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
  - Create the `authelia_gen_access` group, add users to it
  - Uncomment out the authelia middleware
    `vim /etc/opt/traefik/config/dynamic/traefik.yml`

  - Create robot users (Not currently used, ignore for now. Prefer OIDC client)
    - Use `{{ site.email.replace('@', '+USER@') }}` for the email.
    - Use the stored password:
      `/usr/local/bin/get_secret.sh USER_lldap_password`
    - Add the new user to the `lldap_strict_readonly` group

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
ntfy user add hass
ntfy access hass "hass*" rw
ntfy user add person
ntfy access person "hass*" ro
ntfy access person "chat*" rw
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
