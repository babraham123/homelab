#!/usr/bin/env bash
# Prints out the value of a custom secret by ID (for podman).
# Usage:
#   SECRET_ID=XX /usr/local/bin/get_secret_by_id.sh

set -euo pipefail

SECRET_NAME=$(jq -r '.idToName."'$SECRET_ID'"' /var/lib/containers/storage/secrets/secrets.json)

/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | /usr/bin/yq ".$SECRET_NAME" | head -c -1
