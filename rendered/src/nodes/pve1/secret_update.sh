#!/bin/bash
# Edits a host's secrets and, for a VM, installs them on it with placeholder Podman secrets.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/secret_update.sh HOST   # pve1 edits pve1's own

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/nodes/pve1/secrets_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/secrets_lib.sh"

host="$1"
addr="manualadmin@${host}"

require_root
[[ $host == pve1 ]] || require_reachable "$host"

# Record secrets, see template for commands
secret_edit "$host"
[[ $host != pve1 ]] || exit 0
scp "${secrets}/${host}.yaml.age" "${addr}:/home/manualadmin/secrets.yaml.age"

echo "manualadmin's sudo password on ${host}:"
ssh -t "$addr" '
set -euo pipefail
sudo mkdir -p /etc/opt/secrets
sudo mv /home/manualadmin/secrets.yaml.age /etc/opt/secrets/secrets.yaml.age
sudo chown root:root /etc/opt/secrets/secrets.yaml.age

echo "placeholder" > /tmp/placeholder.txt
sudo podman secret rm --all
sudo /root/homelab-rendered/src/base/podman/list_secrets.sh | xargs -I% sudo podman secret create "%" /tmp/placeholder.txt
sudo podman secret ls
'
