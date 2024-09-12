#!/usr/bin/env bash
# Prints out all custom secret names (for podman).
# Usage:
#   /usr/local/bin/list_secrets.sh

set -euo pipefail

/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | /usr/bin/yq -r "keys | .[]"
