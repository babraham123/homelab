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
