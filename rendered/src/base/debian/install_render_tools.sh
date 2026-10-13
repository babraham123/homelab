#!/bin/bash
# Installs the tools that render templates on the node: jinjanator and yq.
# Usage:
#   /root/homelab-rendered/src/base/debian/install_render_tools.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

apt install -y python3-pip
pip3 install --break-system-packages jinjanator jinjanator-plugin-ansible passlib "bcrypt==4.0.1"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" -O - | tar xz
mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
yq --version
