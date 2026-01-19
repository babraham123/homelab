#!/usr/bin/env bash
# Copy the acme.json files from secsvcs, websvcs and homesvcs to pve1. Parse and distribute the
# ACME certificates to pve1, pve2, pbs2, the vpn UI and pfsense.
# Usage:
#   /root/homelab-rendered/src/certificates/acme_transfer.sh
set -euo pipefail

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh vpn
/root/homelab-rendered/src/debian/is_reachable.sh pve2
/root/homelab-rendered/src/debian/is_reachable.sh router

cd /root/acme

function download() {
  host=$1
  addr="manualadmin@$host.{{ site.url }}"
  /root/homelab-rendered/src/debian/is_reachable.sh "$host"

  echo "$host root password:"
  ssh -t "$addr" '
sudo cp /etc/opt/traefik/certificates/acme.json /home/manualadmin/acme.json
sudo chown manualadmin:manualadmin /home/manualadmin/acme.json
'
  scp "$addr:/home/manualadmin/acme.json" "/root/acme/$host.acme.json"
  ssh "$addr" 'rm -f /home/manualadmin/acme.json'
  chmod 400 "$host.acme.json"
  # Ref: https://github.com/ldez/traefik-certs-dumper#use-domain-as-sub-directory
  # Certificate is the full chain (I think)
  /usr/local/bin/traefik-certs-dumper file --domain-subdir \
    --source "$host.acme.json" --dest /root/acme --version v2
}

download "secsvcs"
download "homesvcs"
download "websvcs"

# Ref: https://pve.proxmox.com/wiki/Certificate_Management
cp pve1.{{ site.url }}/certificate.crt /etc/pve/nodes/pve1/pveproxy-ssl.pem
cp pve1.{{ site.url }}/privatekey.key /etc/pve/nodes/pve1/pveproxy-ssl.key
systemctl restart pveproxy.service

scp pve2.{{ site.url }}/certificate.crt manualadmin@pve2.{{ site.url }}:/home/manualadmin/pveproxy-ssl.pem
scp pve2.{{ site.url }}/privatekey.key manualadmin@pve2.{{ site.url }}:/home/manualadmin/pveproxy-ssl.key
# Ref: https://pbs.proxmox.com/wiki/index.php/HTTPS_Certificate_Configuration
scp pbs2.{{ site.url }}/certificate.crt manualadmin@pve2.{{ site.url }}:/home/manualadmin/proxy.pem
scp pbs2.{{ site.url }}/privatekey.key manualadmin@pve2.{{ site.url }}:/home/manualadmin/proxy.key
echo "PVE2 root password:"
ssh -t manualadmin@pve2.{{ site.url }} 'sudo /root/homelab-rendered/src/pve2/install_files.sh certs_and_keys' > pbs2_cert_info.txt

# Update PBS fingerprint for PVE1
# Ref: https://pbs.proxmox.com/docs/pve-integration.html
fingerprint=$(tail -n1 pbs2_cert_info.txt | tr -d '\r')
pvesm set pbs2 --fingerprint "$fingerprint"

# Ref: https://github.com/stompro/pfsense-import-certificate
scp router.{{ site.url }}/certificate.crt admin@router.{{ site.url }}:/root/router.cert.pem
scp router.{{ site.url }}/privatekey.key admin@router.{{ site.url }}:/root/router.key.pem
echo "router admin password:"
ssh -t admin@router.{{ site.url }} '
php /root/pfsense-import-certificate.php /root/router.cert.pem /root/router.key.pem
'

date -u > date_acme_certs.txt
