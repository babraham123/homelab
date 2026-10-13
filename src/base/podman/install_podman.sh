#!/bin/bash
# Installs Podman from the alvistack repo.
# Usage:
#   /root/homelab-rendered/src/base/podman/install_podman.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

source /etc/os-release
curl -fsSL "https://download.opensuse.org/repositories/home:/alvistack/Debian_${VERSION_ID}/Release.key" \
  | gpg --dearmor \
  | tee /etc/apt/trusted.gpg.d/alvistack.gpg > /dev/null
echo "deb http://downloadcontent.opensuse.org/repositories/home:/alvistack/Debian_${VERSION_ID}/ /" \
  | tee /etc/apt/sources.list.d/alvistack.list > /dev/null

apt update
apt -y upgrade
apt -y install podman podman-netavark podman-aardvark-dns podman-compose libgpgme11-dev buildah libyajl2 uidmap
podman --version
