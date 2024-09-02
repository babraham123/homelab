#!/usr/bin/env bash
# Prints out a custom secret by name.
# Usage:
#   /root/homelab-rendered/src/podman/get_secret.sh SECRET_NAME

set -euo pipefail

secret_name="$1"
/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | /usr/bin/yq ".$secret_name"
