# Maintenance
TODO: fill in

All of the commands take place on PVE1
```bash
ssh {{ username }}@pve1.{{ site.url }}
sudo su
```

## Update secrets
```bash
/root/homelab-rendered/src/secsvcs/secret_update.sh
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
