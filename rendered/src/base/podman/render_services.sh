#!/bin/bash
# Renders the given file in the same directory as it's template (FILENAME.j2).
# Includes all configured "Homelab" systemd services as "homelab_services".
# Usage:
#   src/base/podman/render_services.sh FILENAME
# Ref:
# https://github.com/kpfleming/jinjanator

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

file=$1
rm -f "$file"

if [ ! -f "$file.j2" ]; then
  die "file template $file.j2 does not exist"
fi

SVCS=$(echo "homelab_services:"; homelab_services | sed 's/^/  - /')

echo "$SVCS" | jinjanate --quiet --format=yaml -o "$file" "$file.j2"

echo "Rendered the file $file"
