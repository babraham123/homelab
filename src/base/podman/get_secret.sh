#!/bin/bash
# Prints out a custom secret by name.
# Usage:
#   src/base/podman/get_secret.sh SECRET_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

secret_name="$1"
/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | NAME="$secret_name" /usr/bin/yq '.[strenv(NAME)]'
