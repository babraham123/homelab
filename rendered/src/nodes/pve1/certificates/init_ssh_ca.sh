#!/bin/bash
# Creates the SSH user and host CAs and root's client key. Run once, on pve1.
# ssh-keygen prompts for the user CA's passphrase; keep it.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/certificates/init_ssh_ca.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../base/lib.sh"

require_root

mkdir -p /root/ssh/public
cd /root/ssh
chmod 700 public

# Each key only when missing, so a recovery that lost one CA keeps the rest: a new root key
# would orphan the cert ssh_cert_gen.sh logs in to the nodes with
if [[ ! -f ca_ssh_key ]]; then
  ssh-keygen -t ed25519 -f ca_ssh_key -C "SSH CA for janedoe.com"
  chmod 444 ca_ssh_key.pub
  chmod 400 ca_ssh_key
fi

# No passphrase: ssh_cert_gen.sh signs host keys with it unprompted
if [[ ! -f ca_ssh_host_key ]]; then
  ssh-keygen -t ed25519 -f ca_ssh_host_key -C "SSH Host CA for janedoe.com" -N ""
  chmod 444 ca_ssh_host_key.pub
  chmod 400 ca_ssh_host_key
fi

# root's client key, signed by ssh_cert_gen.sh as manualadmin/autoadmin.
# No passphrase: pve1's scripts SSH to the other hosts with it unprompted.
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
fi
