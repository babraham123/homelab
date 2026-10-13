#!/bin/bash
# Installs the Coral TPU PCIe driver and Edge TPU runtime. Reboot afterwards.
# If gasket-dkms fails to build, use build_gasket.sh.
# Usage:
#   /root/homelab-rendered/src/base/debian/install_coral.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root
if lsmod | grep -q apex; then
  die "the apex driver is already loaded"
fi

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | tee /etc/apt/keyrings/google-cloud.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" \
  | tee /etc/apt/sources.list.d/coral-edgetpu.list > /dev/null
apt update
apt install -y gasket-dkms libedgetpu1-std
