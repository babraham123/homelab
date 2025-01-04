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
  addr="{{ username }}@$host.{{ site.url }}"
  /root/homelab-rendered/src/debian/is_reachable.sh "$host"

  echo "$host root password:"
  ssh -t "$addr" '
sudo cp /etc/opt/traefik/certificates/acme.json /home/{{ username }}/acme.json
sudo chown {{ username }}:{{ username }} /home/{{ username }}/acme.json
'
  scp "$addr:/home/{{ username }}/acme.json" "/root/acme/$host.acme.json"
  ssh "$addr" 'rm -f /home/{{ username }}/acme.json'
  chmod 400 "$host.acme.json"
  # Ref: https://github.com/ldez/traefik-certs-dumper#use-domain-as-sub-directory
  # Certificate is the full chain (I think)
  /usr/local/bin/traefik-certs-dumper file --domain-subdir \
    --source "$host.acme.json" --dest /root/acme --version v2
}

download "secsvcs"
download "homesvcs"
download "websvcs"

# Ref: https://www.tecmint.com/configure-ssl-certificate-haproxy/
cat vpn-ui.{{ site.url }}/privatekey.key vpn-ui.{{ site.url }}/certificate.crt > vpn-ui.{{ site.url }}/vpnui.all.pem
scp vpn-ui.{{ site.url }}/vpnui.all.pem {{ username }}@vpn.{{ site.url }}:/home/{{ username }}/vpnui.all.pem
echo "VPN root password:"
ssh -t {{ username }}@vpn.{{ site.url }} 'sudo /root/homelab-rendered/src/vpn/install_files.sh certs'

# Ref: https://pve.proxmox.com/wiki/Certificate_Management
cp pve1.{{ site.url }}/certificate.crt /etc/pve/nodes/pve1/pveproxy-ssl.pem
cp pve1.{{ site.url }}/privatekey.key /etc/pve/nodes/pve1/pveproxy-ssl.key
systemctl restart pveproxy.service

scp pve2.{{ site.url }}/certificate.crt {{ username }}@pve2.{{ site.url }}:/home/{{ username }}/pveproxy-ssl.pem
scp pve2.{{ site.url }}/privatekey.key {{ username }}@pve2.{{ site.url }}:/home/{{ username }}/pveproxy-ssl.key
# Ref: https://pbs.proxmox.com/wiki/index.php/HTTPS_Certificate_Configuration
scp pbs2.{{ site.url }}/certificate.crt {{ username }}@pve2.{{ site.url }}:/home/{{ username }}/proxy.pem
scp pbs2.{{ site.url }}/privatekey.key {{ username }}@pve2.{{ site.url }}:/home/{{ username }}/proxy.key
echo "PVE2 root password:"
ssh -t {{ username }}@pve2.{{ site.url }} 'sudo /root/homelab-rendered/src/pve2/install_files.sh certs_and_keys' > pbs2_cert_info.txt

# Update PBS fingerprint for PVE1
# Ref: https://pbs.proxmox.com/docs/pve-integration.html
fingerprint=$(grep "Fingerprint" pbs2_cert_info.txt | sed -r 's/Fingerprint\s+\(sha256\):\s+([a-f0-9:]+)/\1/')
pvesm set pbs2 --fingerprint "$fingerprint"

# Ref: https://github.com/stompro/pfsense-import-certificate
scp router.{{ site.url }}/certificate.crt admin@router.{{ site.url }}:/root/router.cert.pem
scp router.{{ site.url }}/privatekey.key admin@router.{{ site.url }}:/root/router.key.pem
echo "router admin password:"
ssh -t admin@router.{{ site.url }} '
php /root/pfsense-import-certificate.php /root/router.cert.pem /root/router.key.pem
'

date -u > date_acme_certs.txt
echo -e '\nMake sure to restart haproxy'
