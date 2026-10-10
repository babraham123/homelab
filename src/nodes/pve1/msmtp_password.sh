#!/bin/bash
# Prints out the msmtp password. Needed because msmtprc doesn't support a bash shell.
# Usage:
#   src/pve1/msmtp_password.sh
# Called in place by msmtp (root only), so a deploy updates it; the AppArmor profile
# names this path.

SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub) \
SOPS_AGE_KEY_FILE=/root/secrets/age.txt \
  sops -d /root/secrets/pve1.yaml | yq ".msmtp_password"
