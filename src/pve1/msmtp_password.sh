#!/usr/bin/env bash
# /usr/local/bin/msmtp_password.sh

SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub) \
SOPS_AGE_KEY_FILE=/root/secrets/age.txt \
  sops -d /root/secrets/pve1.yaml | yq ".msmtp_password"
