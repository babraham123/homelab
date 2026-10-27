#!/bin/bash
# Copies the rendered files a particular homelab server uses to it.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/upload_src.sh SUBDOMAIN /dir/to/store/rendered/copy

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

host=$1
project_dir=$2
url=$(yq --yaml-fix-merge-anchor-to-spec=true ".site.url" vars.yml)

if ! ping -c3 -W3 "${host}.${url}" > /dev/null; then
  die "${host} is not reachable"
fi

if [[ "$host" == "router" ]]; then
  echo "router admin password:"
  ssh -t "admin@router.${url}" 'rm -rf /root/router-src'
  scp -qr -o LogLevel=QUIET "${project_dir}/src/nodes/router" "admin@router.${url}:/root/router-src"
  exit 0
fi

if [[ "$host" == "gaming" ]]; then
  echo "gaming admin password:"
  scp -qr -o LogLevel=QUIET "${project_dir}/src/nodes/gaming" "admin@gaming.${url}:C:/Homelab/gaming-src"
  exit 0
fi

# Only the src/ paths this node uses, in the same tree shape so the
# /root/homelab-rendered/src/... paths in its scripts hold
paths=$(cd "$project_dir" && tools/inventory.py dirs "$host")
[ -n "$paths" ] || die "${host} isn't a debian node (tools/inventory.py dirs), so nothing to upload"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "${stage}/homelab-rendered/src"
# shellcheck disable=SC2086 # one path per word
tar -C "${project_dir}/src" -cf - $paths | tar -C "${stage}/homelab-rendered/src" -xf -
[ ! -f "${project_dir}/DEPLOYED" ] || cp "${project_dir}/DEPLOYED" "${stage}/homelab-rendered/"

# vpnsvcs's SSH port comes from ~/.ssh/config (src/base/debian/ssh_config)
scp -qr -o LogLevel=QUIET "${stage}/homelab-rendered" "manualadmin@${host}.${url}:/home/manualadmin"
echo "manualadmin's sudo password on ${host}:"
ssh -t "manualadmin@${host}.${url}" '
sudo chown -R root:root homelab-rendered
sudo rm -rf /root/homelab-rendered
sudo mv homelab-rendered /root/homelab-rendered
sudo /root/homelab-rendered/src/base/debian/record_deploy.sh
'
