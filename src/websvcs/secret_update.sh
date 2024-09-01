#!/usr/bin/env bash
# Updates and installs websvcs custom secrets.
# Usage:
#   /usr/local/bin/secret_websvcs_update.sh

set -euo pipefail

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Record secrets, see template for commands
sops /root/secrets/websvcs.yaml
# SOPS doesn't support SSH keys, must convert before exporting
sops -d /root/secrets/websvcs.yaml | age -e -R /root/secrets/age.pub -R /root/secrets/websvcs_id_ed25519.pub -o /root/secrets/websvcs.yaml.age
chmod 600 /root/secrets/websvcs.yaml
chmod 400 /root/secrets/websvcs.yaml.age
scp /root/secrets/websvcs.yaml.age {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}/secrets.yaml.age

echo "websvcs root password:"
ssh -t {{ username }}@websvcs.{{ site.url }} '
sudo mv /home/{{ username }}/secrets.yaml.age /etc/opt/secrets/secrets.yaml.age
sudo chown root:root /etc/opt/secrets/secrets.yaml.age
'
echo -e '\nMake sure to restart the relevant services'

# If creating a new secret, run the following command on websvcs:
# sudo podman secret create 'SECRET_NAME' /root/placeholder.txt
