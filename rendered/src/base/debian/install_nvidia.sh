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

apt update
apt upgrade -y
apt install -y "linux-headers-$(uname -r)"

wget -O /tmp/cuda-keyring.deb "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb"
dpkg -i /tmp/cuda-keyring.deb
rm /tmp/cuda-keyring.deb
apt update

apt install -y "nvidia-driver-pinning-${version}"
apt install -y cuda-drivers nvtop
