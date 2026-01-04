#!/usr/bin/env bash
# Updates and installs custom secrets.
# Usage:
#   /root/homelab-rendered/src/pve1/secret_update.sh SUBDOMAIN

set -euo pipefail

host="$1"
addr="admin@$host.{{ site.url }}"

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh "$host"

SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub)
export SOPS_AGE_RECIPIENTS
export SOPS_AGE_KEY_FILE="/root/secrets/age.txt"

# Record secrets, see template for commands
sops "/root/secrets/$host.yaml"
# SOPS doesn't support SSH keys, must convert before exporting
sops -d "/root/secrets/$host.yaml" | sudo age -e -R /root/secrets/age.pub -R "/root/secrets/${host}_id_ed25519.pub" -o "/root/secrets/$host.yaml.age"
chmod 600 "/root/secrets/$host.yaml"
chmod 400 "/root/secrets/$host.yaml.age"
scp "/root/secrets/$host.yaml.age" "$addr:/home/admin/secrets.yaml.age"

echo "$host root password:"
ssh -t "$addr" '
sudo mkdir -p /etc/opt/secrets
sudo mv /home/admin/secrets.yaml.age /etc/opt/secrets/secrets.yaml.age
sudo chown root:root /etc/opt/secrets/secrets.yaml.age
'

echo -e '\nMake sure to restart the relevant services\n'
echo 'If creating a new secret, run the following cmd:'
echo 'sudo podman secret create "SECRET_NAME" /root/placeholder.txt'
