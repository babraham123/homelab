#!/bin/bash
# Prints out the value of a custom secret by ID (for podman).
# Usage:
#   SECRET_ID=XX /usr/local/bin/get_secret_by_id.sh

set -euo pipefail

[[ -n "${SECRET_ID:-}" ]] || { echo "SECRET_ID unset" >&2; exit 1; }

SECRET_NAME=$(jq -r --arg id "$SECRET_ID" '.idToName[$id]' /var/lib/containers/storage/secrets/secrets.json)
if [[ "$SECRET_NAME" == "null" ]]; then
  echo "no secret with ID ${SECRET_ID}" >&2
  exit 1
fi

/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | NAME="$SECRET_NAME" /usr/bin/yq '.[strenv(NAME)]' | head -c -1
