#!/bin/bash
# Installs age and SOPS, and creates the AGE key that encrypts every node's secrets.
# Run once, on pve1.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/init_secrets.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root
[[ ! -e /root/secrets ]] || die "/root/secrets already exists"

apt install -y age wget moreutils jq

# The static binary, pinned: the release's checksums list it, not the deb
version=3.13.3
fetch_pinned "https://github.com/getsops/sops/releases/download/v${version}/sops-v${version}.linux.amd64" \
  e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b /tmp/sops
install -D /tmp/sops /usr/local/bin/sops
rm /tmp/sops

for rc in /root/.zshrc /root/.bashrc; do
  # shellcheck disable=SC2016 # expanded by the shell that sources the rc file
  echo -e '\nexport SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub)' >> "$rc"
  echo 'export SOPS_AGE_KEY_FILE="/root/secrets/age.txt"' >> "$rc"
done

mkdir /root/secrets
chmod 700 /root/secrets
cd /root/secrets
age-keygen -o age.txt
age-keygen -y age.txt > age.pub
chmod 400 age.*
