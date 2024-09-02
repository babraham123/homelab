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

function upload() {
  subdomain=$1
  if ! ping -c3 -W3 "$subdomain.$url" > /dev/null; then
    echo "$subdomain is not reachable."
    return
  fi

  scp -qr -o LogLevel=QUIET homelab-rendered "$user@$subdomain.$url:/home/$user"
  echo "$subdomain root password:"
  ssh -t "$user@$subdomain.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'
}

upload "pve2" || true
upload "secsvcs" || true
upload "websvcs" || true
upload "vpn" || true
