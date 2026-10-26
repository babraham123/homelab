#!/bin/bash
# Installs the tools that render templates on the node: jinjanator and yq.
# Usage:
#   /root/homelab-rendered/src/base/debian/install_render_tools.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

apt install -y python3-pip
# passlib needs bcrypt 4.0. Debian's python3-bcrypt, where some package pulled it in, has no
# RECORD for pip to uninstall, so the pin goes into /usr/local beside it, which wins on sys.path.
pip3 install --break-system-packages --ignore-installed "bcrypt==4.0.1"
pip3 install --break-system-packages jinjanator jinjanator-plugin-ansible passlib

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
url="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}"
wget "$url/yq_linux_amd64.tar.gz" "$url/checksums" "$url/checksums_hashes_order"
# checksums has a line per file and a column per hash, in checksums_hashes_order's order
col=$(( $(grep -nx 'SHA-256' checksums_hashes_order | cut -d: -f1) + 1 ))
sha=$(awk -v col="$col" '$1 == "yq_linux_amd64.tar.gz" { print $col }' checksums)
echo "${sha}  yq_linux_amd64.tar.gz" | sha256sum --check || die "checksum mismatch: yq_linux_amd64.tar.gz"
tar xzf yq_linux_amd64.tar.gz
mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
yq --version
