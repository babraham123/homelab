# Maintenance
TODO: fill in

All of the commands take place on PVE1
```bash
ssh {{ username }}@pve1.{{ site.url }}
sudo su
```

## Update secrets
```bash
/root/homelab-rendered/src/pve1/secret_update.sh secsvcs
# if a new secret was added
ssh {{ username }}@secsvcs.{{ site.url }}
sudo podman secret create "SECRET_NAME" /root/placeholder.txt
```

## Refresh certificates
Once every 2 months
```bash
/root/homelab-rendered/src/certificates/acme_transfer.sh
```

Once a year
```bash
/root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
```

## Add a new service
- Update traefik config for that VM
- Internal only route, update unbound config
- service container and configs
- install script
- local cert and key if cross VM communication
  - if it's the server, update cert and key gen scripts
  - otherwise the CA cert should be sufficient
- update guide for that VM
- Authelia config
- Gatus config
- homepage config and icon
