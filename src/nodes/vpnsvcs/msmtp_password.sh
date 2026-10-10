#!/bin/bash
# Prints out the msmtp password, pve1's msmtp_password, hand-placed on this node.
# src/base/certificates/msmtprc.j2 finds it by hostname.
# Usage:
#   src/nodes/vpnsvcs/msmtp_password.sh
# Called in place by msmtp (root only); the AppArmor local override names this path.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cat /etc/opt/secrets/msmtp_password
