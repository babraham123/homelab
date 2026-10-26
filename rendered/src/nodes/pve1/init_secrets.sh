#!/bin/bash
# Installs age and creates the AGE key that encrypts every node's secrets.
# Run once, on pve1.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/init_secrets.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root
[[ ! -e /root/secrets ]] || die "/root/secrets already exists"

apt install -y age moreutils jq

mkdir /root/secrets
chmod 700 /root/secrets
cd /root/secrets
age-keygen -o age.txt
age-keygen -y age.txt > age.pub
chmod 400 age.*
