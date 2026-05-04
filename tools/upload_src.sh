#!/usr/bin/env bash
# Copies the source code to a particular homelab server.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/upload_src.sh SUBDOMAIN /dir/to/store/rendered/copy

set -euo pipefail

host=$1
project_dir=$2
url=$(yq --yaml-fix-merge-anchor-to-spec=true ".site.url" vars.yml)

if ! ping -c3 -W3 "${host}.${url}" > /dev/null; then
  echo "error: ${host} is not reachable" >&2
  return
fi

port="22"
if [[ "$host" == "vpn" ]]; then
  port="2202"
fi

if [[ "$host" == "router" ]]; then
  echo "router admin password:"
  scp -qr -o LogLevel=QUIET "${project_dir}/src/router" "admin@router.${url}:/root/router-src"
  exit 0
fi

if [[ "$host" == "gaming" ]]; then
  echo "gaming admin password:"
  scp -qr -o LogLevel=QUIET "${project_dir}/src/gaming" admin@gaming:'"/c:/Users/admin/gaming-src"'
  exit 0
fi

scp -qr -P "$port" -o LogLevel=QUIET "$project_dir" "manualadmin@${host}.${url}:/home/manualadmin"
echo "${host} root password:"
ssh -p "$port" -t "manualadmin@${host}.${url}" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
'
