# Maintenance

## Restart a service
- Determine which VM it's running on and restart
```bash
ssh manualadmin@secsvcs
sudo systemctl restart SERVICE
```

## Upgrade all systems
Once a year

- WiFi AP firmware
  - Download the firmware bin, [TP-Link EAP660](https://support.omadanetworks.com/en/download/firmware/eap660-hd/v1/)
  - Go to AP's admin console (https://wifi.SITE_URL) >> System >> Firmware Update
  - Make sure to apply every incremental update

TODO: router, all VMs, pinned docker images 

## Upgrade Authelia to a new minor version
`src/authelia/configuration.yml.j2` is the upstream `config.template.yml` with local
values uncommented, and `src/authelia/config.template.yml` is the pristine upstream
copy it was last merged from, so a bump is a three-way merge. `Image=` is pinned to the minor
version, so patch releases arrive through auto-update without a merge.

- Read the release notes for renamed or removed keys
- Merge the new template. Upstream leaves a few example keys uncommented
  (`session.secret`, `identity_validation.reset_password.jwt_secret`), which would
  otherwise conflict with or override local values, so both copies are commented out
  first:
```bash
new=4.40.0
S=$(mktemp -d)
curl -fsSL "https://raw.githubusercontent.com/authelia/authelia/v${new}/config.template.yml" -o "$S/new.yml"
norm() { perl -pe 's/^(\s*)(?![#\s]|---|\.\.\.)(\S)/$1# $2/' "$1"; }
norm src/authelia/config.template.yml > "$S/base.norm.yml"
norm "$S/new.yml" > "$S/new.norm.yml"
git merge-file -L local -L base -L "v${new}" src/authelia/configuration.yml.j2 "$S/base.norm.yml" "$S/new.norm.yml"
cp "$S/new.yml" src/authelia/config.template.yml
```
- Resolve the conflicts: keep local values, take upstream's comment text
- Set the `# v<version>` header in `configuration.yml.j2` and the `Image=` tag in
  `authelia.container.j2` to the new minor version; rendering fails if their minor versions
  differ
- Render and upload, then validate with the new image before installing. The `sed`
  passes the quadlet's secrets and environment so the template filter can run:
```bash
ssh manualadmin@secsvcs
cd /root/homelab-rendered/src/authelia
sudo podman run --rm \
  $(sed -nE 's/^Secret=/--secret=/p; s/^Environment=/--env=/p' authelia.container) \
  -v "$PWD":/config:ro -v /etc/opt/authelia/certificates:/certificates:ro \
  "$(sed -n 's/^Image=//p' authelia.container)" \
  authelia config validate --config /config/configuration.yml
sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh authelia
```
- Check login, OIDC login to Grafana, and a ForwardAuth-protected route

## Add a new user
TODO: code edits, lldap for new user

## Update secrets
```bash
ssh manualadmin@pve1
sudo /root/homelab-rendered/src/pve1/secret_update.sh secsvcs
```

## Refresh certificates
You should receive email notifications several weeks in advance of certificate expiration.

- Once every 2 months
```bash
ssh manualadmin@pve1
# Copy over the ACME generated certs 
sudo /root/homelab-rendered/src/certificates/acme_transfer.sh
```

- Once a year
```bash
ssh manualadmin@pve1
# Generate self signed certs
sudo /root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
# Generate SSH certs
sudo /root/homelab-rendered/src/certificates/ssh_cert_gen.sh
# Generate SSH certs for the Gaming VM
ssh autoadmin@router start_pve2
ssh autoadmin@pve2 start_gaming_vm
sudo /root/homelab-rendered/src/certificates/ssh_cert_gen_windows.sh
```

## Disaster recovery
- pve1's SSD died, or its AGE key, private CA, SSH CA or `vars.yml` is gone: [pve1 disaster recovery](guides/pve1_recovery.md)
