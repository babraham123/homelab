#!/bin/bash
# Prefixes the service's description with "Homelab: "
# Usage:
#   src/base/debian/add_homelab_tag.sh SYSTEMD_FILE.service

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

if grep -q "Description=\"Homelab: " "$1"; then
  exit 0
fi

sed -ri'' 's/^Description=["'\'']?([^"'\'']*)["'\'']?$/Description="Homelab: \1"/' "$1"
