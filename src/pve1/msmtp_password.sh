#!/usr/bin/env bash
# Prints out the msmtp password. Needed because msmtprc doesn't support a bash shell.
# Usage:
#   /usr/local/bin/msmtp_password.sh

SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub) \
SOPS_AGE_KEY_FILE=/root/secrets/age.txt \
  sops -d /root/secrets/pve1.yaml | yq ".msmtp_password"
