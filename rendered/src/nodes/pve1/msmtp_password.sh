#!/bin/bash
# Prints out the msmtp password. Needed because msmtprc doesn't support a bash shell.
# Usage:
#   src/nodes/pve1/msmtp_password.sh
# Called in place by msmtp (root only), so a deploy updates it; the AppArmor profile
# names this path.

age -d -i /root/secrets/age.txt /root/secrets/pve1.yaml.age | yq ".msmtp_password"
