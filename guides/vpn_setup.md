# VPN setup

- Buy a domain name from a DNS registrar / provider (ie Namecheap)
	- In the future may need to use Cloudflare as the provider (while using the existing registrar)

## Linode
- Setup smallest, CPU shared VM in [Linode](https://www.linode.com/)
- [Basic setup](./debian_setup.md), `ssh root@{{ vpn.ip }}`
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
src/vpn/install_svcs.sh headscale
cp src/headscale/headscale_private.yaml /etc/headscale/config.yaml
systemctl restart headscale
```

- Create an A record in Namecheap that maps your `vpn` subdomain to Linode's public IP ([src](https://www.namecheap.com/support/knowledgebase/article.aspx/9776/2237/how-to-create-a-subdomain-for-my-domain/))
- Create pre-auth key
```bash
headscale completion bash > /etc/bash_completion.d/headcompletion
headscale users create {{ username }}
headscale --user {{ username }} preauthkeys create --reusable --expiration 24h
```

## Clients
- For home network, use Tailscale plugin on pfSense ([src](https://www.wundertech.net/how-to-set-up-tailscale-on-pfsense/))
	- Setup as an [Exit Node](https://headscale.net/exit-node/) for the desired subnet
	- Restart pfSense ([issue](https://github.com/tailscale/tailscale/issues/7780))
	- On the VPN server, enable pfSense's routes
```bash
headscale routes list
# Repeat for all desired subnets
headscale routes enable -r 1
# Create users
{% for user in users %}
headscale users create {{ user }}
{% endfor %}
headscale users create guest1
```
- For MacOS, use Tailscale app ([src](https://github.com/juanfont/headscale/blob/main/hscontrol/templates/apple.html)), or
```bash
brew install tailscale
sudo /opt/homebrew/opt/tailscale/bin/tailscaled
tailscale login --login-server https://vpn.{{ site.url }}:443 --accept-routes --auth-key AUTH_KEY

tailscale status
tailscale ping --tsmp other_node
# sudo tailscale set --exit-node=pfsense
```
- For Debian bookworm ([src](https://tailscale.com/kb/1174/install-debian-bookworm))
```bash
src/vpn/install_svcs.sh tailscale
sudo tailscale up --login-server https://vpn.{{ site.url }}:443 --accept-routes --authkey AUTH_KEY
# --exit-node=pfsense
```
- In cloud VM, check connected nodes: `sudo headscale nodes list`

## Add public endpoint
Summary: Create a public user and a tailscale client on the vpn server. HAProxy forwards the `vpn` subdomain to Headscale on ports 8080, 8443. Vaultwarden, authelia, lldap and home assistant traffic is sent to the secsvcs VM via a local traefik instance (reverse proxy). All other traffic is sent to the websvcs VM also via traefik. Similar to Tailscale Funnel, and fulfills a similar role as a DMZ.

Notes: [site-to-site](https://tailscale.com/kb/1214/site-to-site/), [ACLs](https://tailscale.com/kb/1018/acls/#debugging-acls), [troubleshooting](https://tailscale.com/kb/1023/troubleshooting/#unable-to-make-a-tcp-connection-between-two-nodes)

- Route traffic via HAProxy
```bash
sudo su
cd /root/homelab-rendered
src/vpn/install_svcs.sh haproxy
```
- Update Headscale
  - `src/vpn/install_svcs.sh headscale`
- Update Namecheap A record
	- Change the host from `vpn` to all subdomains `*`
	- Add another A record for the bare domain, host = `@`

- Add a Namecheap CAA record, [ref](https://really-simple-ssl.com/instructions/edit-dns-caa-records-to-allow-lets-encrypt-ssl-certificates/)
```
@ issue		letsencrypt.org
@ issuewild	letsencrypt.org
@ iodep		mailto:{{ site.email }}
```
- Create public user and connect, [ref](https://tailscale.com/kb/1080/cli/#up), [snat](https://tailscale.com/kb/1214/site-to-site)
```bash
# Create user
headscale users create public
# Setup client
src/vpn/install_svcs.sh tailscale
headscale --user public preauthkeys create --reusable --expiration 24h
tailscale up --login-server https://vpn.{{ site.url }}:443 --accept-routes --snat-subnet-routes=false --authkey AUTH_KEY
# Clamp MTU
iptables -t mangle -A FORWARD -i tailscale0 -o {{ vpn.interface }} -p tcp -m tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Hack ACLs via ufw, order of precedence = ASC 
ufw reset
ufw default deny incoming
ufw default deny outgoing
ufw allow out 53
ufw allow out on {{ vpn.interface }}
ufw allow in from any to any port 22,80,443 proto tcp
ufw allow in from any to any port 3478,41641 proto udp
ufw allow out on tailscale0 from any to {{ websvcs.ip }} port 80,443 proto tcp
ufw allow out on tailscale0 from any to {{ secsvcs.ip }} port 80,443 proto tcp

# insert before the COMMIT
vim /etc/ufw/before.rules
```
```
# allow outbound icmp
-A ufw-before-output -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
-A ufw-before-output -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT
```
```bash
ufw enable
ufw status verbose
```

## Headscale UI (optional)
- TODO: switch to Podman
- Generate and store the secrets
```bash
mkdir -p /etc/opt/secrets
chmod 700 /etc/opt/secrets
headscale apikeys create | tail -n 1 > /etc/opt/secrets/headscale_api_key
openssl rand -base64 32 > /etc/opt/secrets/hs_ui_storage_key
# Grab the raw version of the oidc secret from the steps below
vim /etc/opt/secrets/hs_ui_oidc_secret
chmod 600 /etc/opt/secrets/*
exit
exit
```
- Create the new secret
```bash
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo podman run docker.io/authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986'
# Store hashed and raw version of secret
ssh -t {{ username }}@pve1.{{ site.url }} 'sudo /usr/local/bin/secret_secsvcs_update.sh'
# Restart authelia to pick up hashed secret version
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo systemctl restart authelia'
```
- Deploy on the VPN server
```bash
ssh {{ username }}@{{ vpn.ip }}
sudo su
apt install -y gcc python3-poetry
mkdir -p /var/opt/headscale-ui/data
cd /var/opt/headscale-ui
HSUI_VERSION=$(curl -s "https://api.github.com/repos/iFargle/headscale-webui/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/iFargle/headscale-webui/archive/refs/tags/v${HSUI_VERSION}.tar.gz" -O - | tar xz
mv "headscale-webui-${HSUI_VERSION}"/* .
poetry install --only main

cp /root/homelab-rendered/src/headscale/headscale-ui.service /etc/systemd/system
systemctl enable headscale-ui.service
systemctl start headscale-ui.service
journalctl -eu headscale-ui
```
