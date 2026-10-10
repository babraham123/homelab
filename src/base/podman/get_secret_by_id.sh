#!/bin/bash
# Prints out the value of a custom secret by ID (for podman).
# Usage:
#   SECRET_ID=XX src/base/podman/get_secret_by_id.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

[[ -n "${SECRET_ID:-}" ]] || die "SECRET_ID unset"

SECRET_NAME=$(jq -r --arg id "$SECRET_ID" '.idToName[$id]' /var/lib/containers/storage/secrets/secrets.json)
if [[ "$SECRET_NAME" == "null" ]]; then
  die "no secret with ID ${SECRET_ID}"
fi

"$(dirname "$0")/get_secret.sh" "$SECRET_NAME" | head -c -1
