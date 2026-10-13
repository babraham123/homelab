#!/bin/bash
# Installs the self-signed CA chain on every Linux host. vpnsvcs's SSH port comes from
# the ssh_config that ssh_cert_gen.sh installed on pve1.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/certificates/upload_ca_chain.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../base/lib.sh"

hosts=(pve1 pve2 vpnsvcs secsvcs homesvcs websvcs devtop)
require_root
require_reachable "${hosts[@]}"

for host in "${hosts[@]}"; do
  log "Installing the CA chain on ${host}"
  "${rendered}/base/debian/send_files.sh" /root/ca/intermediate/certs/ca-chain.cert.pem \
    | ssh "autoadmin@${host}" install_ca
done
