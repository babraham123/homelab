# Maintenance

TODO: fill in

## Update the web services
- Render and upload the configs
```bash
tools/deploy_src.sh
```
- Re-install the relevant services
```bash
ssh {{ username }}@secsvcs.{{ site.url }}
sudo /root/homelab-rendered/src/secsvcs/install_svcs.sh SERVICE
```

## Upgrade all systems
Once a year

- WiFi AP firmware
  - Download the firmware bin, [TP-Link EAP660](https://support.omadanetworks.com/en/download/firmware/eap660-hd/v1/)
  - Go to [admin console](https://wifi.{{ site.url }}) >> System >> Firmware Update
  - Make sure to apply each incremental update

TODO: router, all VMs, pinned docker images 

## Add a new user
TODO

The rest of the commands take place on PVE1
```bash
ssh {{ username }}@pve1.{{ site.url }}
sudo su
```

## Update secrets
```bash
/root/homelab-rendered/src/pve1/secret_update.sh secsvcs
```

If a new secret was added
```bash
ssh {{ username }}@secsvcs.{{ site.url }}
sudo podman secret create "SECRET_NAME" /root/placeholder.txt
```

## Refresh certificates
You should receive email notifications several weeks in advance of certificate expiration.

- Once every 2 months
```bash
/root/homelab-rendered/src/certificates/acme_transfer.sh
```

- Once a year
```bash
/root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
```
