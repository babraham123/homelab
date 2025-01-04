#!/usr/bin/env bash
# Copies the source code to a particular homelab server.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/upload_src.sh SUBDOMAIN /dir/to/store/rendered/copy

set -euo pipefail

host=$1
project_dir=$2
user=$(yq ".username" vars.yml)
url=$(yq ".site.url" vars.yml)

if ! ping -c3 -W3 "$host.$url" > /dev/null; then
  echo "error: $host is not reachable" >&2
  return
fi

scp -qr -o LogLevel=QUIET "$project_dir" "$user@$host.$url:/home/$user"
echo "$host root password:"
ssh -t "$user@$host.$url" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'