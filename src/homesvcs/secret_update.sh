#!/usr/bin/env bash
# Updates and installs homesvcs custom secrets.
# Usage:
#   /root/homelab-rendered/src/homesvcs/secret_update.sh

set -euo pipefail

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh homesvcs

# Record secrets, see template for commands
sops /root/secrets/homesvcs.yaml
# SOPS doesn't support SSH keys, must convert before exporting
sops -d /root/secrets/homesvcs.yaml | sudo age -e -R /root/secrets/age.pub -R /root/secrets/homesvcs_id_ed25519.pub -o /root/secrets/homesvcs.yaml.age
chmod 600 /root/secrets/homesvcs.yaml
chmod 400 /root/secrets/homesvcs.yaml.age
scp /root/secrets/homesvcs.yaml.age {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}/secrets.yaml.age

echo "homesvcs root password:"
ssh -t {{ username }}@homesvcs.{{ site.url }} '
sudo mv /home/{{ username }}/secrets.yaml.age /etc/opt/secrets/secrets.yaml.age
sudo chown root:root /etc/opt/secrets/secrets.yaml.age
'
echo -e '\nMake sure to restart the relevant services'

# If creating a new secret, run the following command on homesvcs:
# sudo podman secret create 'SECRET_NAME' /root/placeholder.txt
