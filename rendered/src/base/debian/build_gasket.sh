#!/bin/bash
# Builds and installs the Coral gasket driver from source, for kernels the packaged
# gasket-dkms doesn't build on. Reboot afterwards.
# Usage:
#   /root/homelab-rendered/src/base/debian/build_gasket.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

apt purge -y gasket-dkms || true

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# The packaged libbpf is too old for pahole
apt install -y build-essential pkg-config libelf-dev zlib1g-dev
libbpf_version=1.5.0
wget "https://github.com/libbpf/libbpf/archive/refs/tags/v${libbpf_version}.tar.gz" -O - | tar xz
cd "libbpf-${libbpf_version}/src"
make
make install
make install PREFIX=/usr LIBDIR=/lib/x86_64-linux-gnu
cd "$tmp"
ldconfig
apt install -y dwarves
pahole --version

apt install -q -y --no-install-recommends git curl devscripts dkms dh-dkms build-essential debhelper
git clone https://github.com/feranick/gasket-driver
cd gasket-driver
debuild -us -uc -tc -b
cd "$tmp"
chmod 644 ./gasket-dkms_*_all.deb
apt install -y ./gasket-dkms_*_all.deb
