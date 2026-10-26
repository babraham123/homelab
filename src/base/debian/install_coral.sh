#!/bin/bash
# Builds and installs the Coral TPU PCIe driver (gasket) from source. Reboot afterwards.
# Google's apt repo is gone; the Edge TPU runtime ships in the images that use the TPU.
# Usage:
#   /root/homelab-rendered/src/base/debian/install_coral.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

rm -f /etc/apt/sources.list.d/coral-edgetpu.list /etc/apt/keyrings/google-cloud.gpg
apt purge -y gasket-dkms || true

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# The packaged libbpf is too old for pahole
apt update
apt install -y build-essential pkg-config libelf-dev zlib1g-dev
libbpf_version=1.5.0
fetch_pinned "https://github.com/libbpf/libbpf/archive/refs/tags/v${libbpf_version}.tar.gz" \
  53492aff6dd47e4da04ef5e672d753b9743848bdb38e9d90eafbe190b7983c44 libbpf.tar.gz
tar xzf libbpf.tar.gz
cd "libbpf-${libbpf_version}/src"
make
make install
make install PREFIX=/usr LIBDIR=/lib/x86_64-linux-gnu
cd "$tmp"
ldconfig
apt install -y dwarves
pahole --version

# Google's gasket-driver doesn't build on current kernels; feranick's fork does
apt install -q -y --no-install-recommends git curl devscripts dkms dh-dkms build-essential debhelper
git clone https://github.com/feranick/gasket-driver
cd gasket-driver
debuild -us -uc -tc -b
cd "$tmp"
chmod 644 ./gasket-dkms_*_all.deb
apt install -y "${tmp}"/gasket-dkms_*_all.deb
