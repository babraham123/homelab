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

file="${secrets}/${host}.yaml.age"
before=$(sha256sum "$file" 2> /dev/null || true)
# Record secrets, see template for commands
secret_edit "$host"
[[ $host != pve1 ]] || exit 0
# An earlier run may have saved edits and stopped before pushing them, e.g. at the sudo prompt
if [[ $(sha256sum "$file") == "$before" ]]; then
  read -rp "No changes. Push ${host}'s secrets anyway? [y/N] " push
  [[ $push == [yY] ]] || exit 0
fi
echo "manualadmin's sudo password on ${host}:"
# The file rides in the command, base64'd, and is written as root, so no copy lands where
# manualadmin, whose SSH key also decrypts it, could read it. Written beside the old one,
# then moved over it, so lookups never see a partial file.
ssh -t "$addr" "secrets_b64=$(base64 -w0 "$file")"'
set -euo pipefail
sudo -v
sudo mkdir -p -m 700 /etc/opt/secrets
base64 -d <<< "$secrets_b64" |
  sudo install -m 400 -o root -g root /dev/stdin /etc/opt/secrets/secrets.yaml.age.new
sudo mv /etc/opt/secrets/secrets.yaml.age.new /etc/opt/secrets/secrets.yaml.age

sudo podman secret rm --all
sudo /root/homelab-rendered/src/base/podman/list_secrets.sh | while read -r name; do
  echo placeholder | sudo podman secret create "$name" -
done
sudo podman secret ls
'
