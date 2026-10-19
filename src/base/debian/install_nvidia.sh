#!/bin/bash
# Installs a pinned Nvidia driver and CUDA from Nvidia's network repo. Reboot afterwards.
# Use debian12 as the distro if the driver version isn't packaged for this release.
# Usage:
#   /root/homelab-rendered/src/base/debian/install_nvidia.sh [DRIVER_VERSION] [DISTRO]

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

source /etc/os-release
version=${1:-580}
distro=${2:-debian${VERSION_ID}}

# The debian12 repo's key is bound by a SHA1 signature, which apt rejects after the cutoff.
# A forgery needs a SHA1 second preimage, so push the cutoff back; the date forces a review.
sha1_cutoff=2027-02-01
if [[ $distro != "debian${VERSION_ID}" ]]; then
  policy=/etc/crypto-policies/back-ends/apt-sequoia.config
  [[ -f $policy ]] || install -D -m 644 /usr/share/apt/default-sequoia.config "$policy"
  # Only the date changes, so the file's quoting stays as shipped
  sed -i "s/^\(sha1\.second_preimage_resistance\s*=\s*\"\?\)[0-9-]*/\1${sha1_cutoff}/" "$policy"
  grep -q "^sha1\.second_preimage_resistance\s*=\s*\"\?${sha1_cutoff}" "$policy" ||
    die "no sha1.second_preimage_resistance line in ${policy}"
fi

apt update
apt upgrade -y
apt install -y "linux-headers-$(uname -r)"

wget -O /tmp/cuda-keyring.deb "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb"
dpkg -i /tmp/cuda-keyring.deb
rm /tmp/cuda-keyring.deb
apt update

apt install -y "nvidia-driver-pinning-${version}"
apt install -y cuda-drivers nvtop
