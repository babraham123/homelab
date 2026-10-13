#!/bin/bash
# Installs the Nvidia container toolkit and generates the CDI spec, so containers can
# request the GPU. Install the driver first (src/base/debian/install_nvidia.sh).
# Usage:
#   /root/homelab-rendered/src/base/podman/install_nvidia_toolkit.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

apt update
apt install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1

nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# The device names the quadlets reference
nvidia-ctk cdi list
