#!/bin/bash
# Prints out all custom secret names (for podman).
# Usage:
#   src/base/podman/list_secrets.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | /usr/bin/yq -r "keys | .[]"
