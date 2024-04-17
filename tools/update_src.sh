#!/usr/bin/env bash
# Run from root of project directory
# tools/update_src.sh

set -euo pipefail

user=$(yq ".username" vars.yml)
url=$(yq ".site.url" vars.yml)

rm -rf /root/homelab-rendered
git pull
tools/render_src.sh /root/homelab-rendered

# Copy rendered files to other servers
cd /root
scp -qr homelab-rendered "$user@pve2.$url:/home/$user"
echo "PVE2 root password:"
ssh -t "$user@pve2.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr homelab-rendered "$user@secsvcs.$url:/home/$user"
echo "secsvcs root password:"
ssh -t "$user@secsvcs.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr homelab-rendered "$user@websvcs.$url:/home/$user"
echo "websvcs root password:"
ssh -t "$user@websvcs.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr homelab-rendered "$user@vpn.$url:/home/$user"
echo "VPN root password:"
ssh -t "$user@vpn.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'
