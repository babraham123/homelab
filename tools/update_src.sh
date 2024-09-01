#!/usr/bin/env bash
# Renders the source code and copies it to other servers.
# Run from root of the project directory on PVE1.
# Usage:
#   cd /root/homelab
#   tools/update_src.sh

set -euo pipefail

user=$(yq ".username" vars.yml)
url=$(yq ".site.url" vars.yml)

rm -rf /root/homelab-rendered
git fetch origin
# Set to whatever the current branch is. Default: main
git reset --hard origin/HEAD
tools/render_src.sh /root/homelab-rendered

# Copy rendered files to other servers
cd /root
scp -qr -o LogLevel=QUIET homelab-rendered "$user@pve2.$url:/home/$user"
echo "PVE2 root password:"
ssh -t "$user@pve2.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr -o LogLevel=QUIET homelab-rendered "$user@secsvcs.$url:/home/$user"
echo "secsvcs root password:"
ssh -t "$user@secsvcs.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr -o LogLevel=QUIET homelab-rendered "$user@websvcs.$url:/home/$user"
echo "websvcs root password:"
ssh -t "$user@websvcs.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'

scp -qr -o LogLevel=QUIET homelab-rendered "$user@vpn.$url:/home/$user"
echo "VPN root password:"
ssh -t "$user@vpn.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'
