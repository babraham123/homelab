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
# alvistack versions everything with epoch 100, so unpinned it replaces Debian's python3-*, zstd,
# etc. on every upgrade, with file layouts that collide with Debian's split packages.
cat > /etc/apt/preferences.d/alvistack <<'EOF'
Package: *
Pin: origin downloadcontent.opensuse.org
Pin-Priority: 100

Package: podman* buildah skopeo containers-common containers-storage containernetworking cri-o-runc crun conmon catatonit passt fuse-overlayfs slirp4netns
Pin: origin downloadcontent.opensuse.org
Pin-Priority: 500
EOF

apt update
apt -y upgrade
apt -y install podman podman-netavark podman-aardvark-dns podman-compose libgpgme11-dev buildah libyajl2 uidmap
# The quadlets are systemd's to start, so this unit has nothing to start at boot, and a podman
# upgrade's postinst restarts it, whose ExecStop stops and removes every container. Masking
# leaves a running instance alone; `disable --now` would run that ExecStop.
systemctl mask podman-restart.service
podman --version
