#!/usr/bin/env bash
# Updates and installs secsvcs custom secrets.
# Usage:
#   /root/homelab-rendered/src/secsvcs/secret_update.sh

set -euo pipefail

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh secsvcs

# Record secrets, see template for commands
sops /root/secrets/secsvcs.yaml
# SOPS doesn't support SSH keys, must convert before exporting
sops -d /root/secrets/secsvcs.yaml | sudo age -e -R /root/secrets/age.pub -R /root/secrets/secsvcs_id_ed25519.pub -o /root/secrets/secsvcs.yaml.age
chmod 600 /root/secrets/secsvcs.yaml
chmod 400 /root/secrets/secsvcs.yaml.age
scp /root/secrets/secsvcs.yaml.age {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}/secrets.yaml.age

echo "secsvcs root password:"
ssh -t {{ username }}@secsvcs.{{ site.url }} '
sudo mv /home/{{ username }}/secrets.yaml.age /etc/opt/secrets/secrets.yaml.age
sudo chown root:root /etc/opt/secrets/secrets.yaml.age
'

echo -e '\nMake sure to restart the relevant services\n'
echo 'If creating a new secret, run the following cmd:'
echo 'sudo podman secret create "SECRET_NAME" /root/placeholder.txt'
