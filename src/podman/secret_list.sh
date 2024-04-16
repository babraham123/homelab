#!/usr/bin/env bash
# /usr/local/bin/secret_list.sh

set -euo pipefail

/usr/bin/age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | /usr/bin/yq -r "keys | .[]"
