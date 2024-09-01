#!/usr/bin/env bash
# Prefixes the service's description with "Homelab: "
# Usage:
#   src/debian/add_homelab_tag.sh SYSTEMD_FILE.service


if grep -q "Description=\"Homelab: " "$1"; then
  exit 0
fi

sed -ri'' 's/^Description=["'\'']?([^"'\'']*)["'\'']?$/Description="Homelab: \1"/' "$1"
