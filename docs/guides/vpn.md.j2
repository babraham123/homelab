# VPN setup

- Buy a domain name from a DNS registrar / provider (ie Namecheap)
  - In the future may need to use Cloudflare as the provider (while using the existing registrar)

## Linode
- Setup smallest, CPU shared VM in [Linode](https://www.linode.com/)
- Basic [Debian Linux setup](./debian.md)
  - `ssh root@{{ vpn.ip }}`
- Firewall rules
```bash
sudo su
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 3478
ufw allow 41641
ufw enable
```
- Block brute force attempts
```bash
cd /root/homelab-rendered
apt install -y fail2ban python3-systemd
cp src/debian/jail.local /etc/fail2ban
systemctl enable fail2ban
systemctl restart fail2ban
```
- Setup Headscale ([src](https://headscale.net/running-headscale-linux/))
```bash
mkdir -p /etc/opt/secrets
chmod 711 /etc/opt/secrets
src/vpn/install_svcs.sh headscale
cp src/headscale/headscale_private.yaml /etc/headscale/config.yaml
systemctl restart headscale
```

- Create an A record in your DNS provider that maps the `vpn` subdomain to Linode's public IP ([src](https://www.namecheap.com/support/knowledgebase/article.aspx/9776/2237/how-to-create-a-subdomain-for-my-domain/))
- Create pre-auth key
```bash
headscale completion bash > /etc/bash_completion.d/headcompletion
headscale users create admin@
headscale --user USER_ID preauthkeys create --expiration 100y
```

## Remote access
- For home network, use Tailscale plugin on pfSense ([src](https://www.wundertech.net/how-to-set-up-tailscale-on-pfsense/), [ref](https://davidisaksson.dev/posts/tailscale-on-pfsense/))
  - Install the Tailscale package (Go to System >> Package Manager)
  - Go to VPN >> Tailscale
  - Setup as an [Exit Node](https://headscale.net/exit-node/) for the desired subnet
  - Restart pfSense ([issue](https://github.com/tailscale/tailscale/issues/7780))
  - On the VPN server, enable pfSense's routes, [ref](https://headscale.net/stable/ref/routes/)
```bash
headscale nodes list-routes
# Repeat for all desired subnets
headscale nodes approve-routes --identifier NODE_ID --routes 0.0.0.0/0,::/0
headscale nodes approve-routes --identifier NODE_ID --routes 192.168.5.0/24
headscale nodes approve-routes --identifier NODE_ID --routes 192.168.7.0/24
```

- At this point you can connect via "machine" users. Skip farther down if you don't want public access.

## Add public endpoint
Summary: Create a public user and a tailscale client on the vpn server. HAProxy forwards the `vpn` subdomain to Headscale on ports 8080, 8443. authelia, lldap, etc traffic is sent to the secsvcs VM, and home assistant traffic to the homesvcs VM. All other traffic is sent to the websvcs VM also via traefik. Similar to Tailscale Funnel, and fulfills a similar role as a DMZ. This also enables OIDC access.

Notes: [site-to-site](https://tailscale.com/kb/1214/site-to-site/), [ACLs](https://tailscale.com/kb/1018/acls/#debugging-acls), [troubleshooting](https://tailscale.com/kb/1023/troubleshooting/#unable-to-make-a-tcp-connection-between-two-nodes)

- Create the OIDC credentials
```bash
exit
exit
ssh manualadmin@secsvcs.{{ site.url }}
sudo podman run --rmi docker.io/authelia/authelia:latest authelia crypto rand --length 72 --charset rfc3986
sudo podman run docker.io/authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986
# Store hashed and raw version of secret under hs_oidc_secret(_hash). id under hs_oidc_id
ssh -t manualadmin@pve1.{{ site.url }} 'sudo /root/homelab-rendered/src/pve1/secret_update.sh secsvcs'
# Restart authelia to pick up hashed secret version
sudo systemctl restart authelia
exit
```

- Store the secrets
```bash
ssh manualadmin@{{ vpn.ip }}
sudo su
# Grab the oidc client id and the raw version of the client secret from the steps above
vim /etc/opt/secrets/hs_oidc_id
vim /etc/opt/secrets/hs_oidc_secret
chown headscale:headscale /etc/opt/secrets/hs_oidc_*
chmod 600 /etc/opt/secrets/*
```

- Route traffic via HAProxy
```bash
sudo su
cd /root/homelab-rendered
src/vpn/install_svcs.sh haproxy
```
- Update Headscale
  - `src/vpn/install_svcs.sh headscale`
- Update your DNS A record
  - Change the host from `vpn` to all subdomains `*`
  - Add another A record for the bare domain, host = `@`

- Add a DNS CAA record, [ref](https://really-simple-ssl.com/instructions/edit-dns-caa-records-to-allow-lets-encrypt-ssl-certificates/)
```
@ issue      letsencrypt.org
* issue      letsencrypt.org
@ issuewild  ;
* issuewild  ;
@ iodep      mailto:{{ site.email }}
* iodep      mailto:{{ site.email }}
```

- Create public user and connect, [ref](https://tailscale.com/kb/1080/cli/#up), [snat](https://tailscale.com/kb/1214/site-to-site)
```bash
# Create user
headscale users create public
headscale --user USER_ID preauthkeys create --expiration 100y
# Setup client
src/vpn/install_svcs.sh tailscaled
tailscale up --login-server https://vpn.{{ site.url }}:443 --accept-routes --snat-subnet-routes=false --authkey AUTH_KEY
# Clamp MTU
NET_IFACE=$(ip -j -4 route show to default | jq -r '.[0].dev')
iptables -t mangle -A FORWARD -i tailscale0 -o $NET_IFACE -p tcp -m tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Hack ACLs via ufw, order of precedence = ASC 
ufw reset
ufw default deny incoming
ufw default deny outgoing
ufw allow out 53
ufw allow out on $NET_IFACE
ufw allow in from any to any port 22,80,443 proto tcp
ufw allow in from any to any port 3478,41641 proto udp
ufw allow out on tailscale0 from any to {{ secsvcs.ip }} port 80,443 proto tcp
ufw allow out on tailscale0 from any to {{ homesvcs.ip }} port 80,443 proto tcp
ufw allow out on tailscale0 from any to {{ websvcs.ip }} port 80,443 proto tcp

# Add permanent iptables rules
echo "NET_IFACE_REPLACE_ME = $(ip -j -4 route show to default | jq -r '.[0].dev')"
vim /etc/ufw/before.rules
```
```
# clamp Tailscale MSS, insert before the *filter
*mangle
:FORWARD ACCEPT [0:0]
-A FORWARD -i tailscale0 -o NET_IFACE_REPLACE_ME -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT

...

# allow outbound ICMP, insert before the COMMIT
-A ufw-before-output -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
-A ufw-before-output -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT
```
```bash
ufw enable
ufw status verbose
```

### Optimize search results

- Log into the `Google Search Console` under {{ site.email }} or another gmail account
- Start verification, enter {{ site.url }}
- In your DNS provider, add a TXT record with the provided string (use host = @)
- View the insights report

## Machine users (optional)
- Create user and key
```bash
headscale users create USERNAME@
headscale --user USER_ID preauthkeys create --expiration 2h
```

- For MacOS, use [Tailscale app](https://headscale.net/stable/usage/connect/apple/), then login
```bash
echo 'alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"' >> ~/.zshrc
tailscale login --login-server https://vpn.{{ site.url }}:443 --accept-routes --auth-key AUTH_KEY

tailscale status
tailscale ping --tsmp other_node
# sudo tailscale set --exit-node=router
```

- For an Apple TV, use the Tailscale app. [Ref](https://tailscale.com/kb/1280/appletv)

- For Debian ([src](https://tailscale.com/kb/1626/install-debian-trixie))
```bash
src/vpn/install_svcs.sh tailscaled
sudo tailscale up --login-server https://vpn.{{ site.url }}:443 --accept-routes --authkey AUTH_KEY
# --exit-node=router
```

- In cloud VM, check connected nodes: `sudo headscale nodes list`

## Upgrade
[Headscale docs](https://github.com/juanfont/headscale/blob/main/docs/setup/upgrade.md)

- Backup the headscale DB
```bash
sudo su
systemctl stop headscale
cd /root/backups
cp /var/lib/headscale/db.sqlite* .
tar -czf db-$(date -I).tar.gz db.sqlite*
rm db.sqlite*
systemctl start headscale
```
