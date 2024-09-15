#!/usr/bin/env bash
# Renders the given file in the same directory as it's template (FILENAME.j2).
# Includes all configured "Homelab" systemd services as "homelab_services".
# Usage:
#   /usr/local/bin/render_services.sh FILENAME
# Ref:
# https://github.com/kpfleming/jinjanator

set -euo pipefail

file=$1
if [ ! -f "$file.j2" ]; then
  echo "error: file template $file.j2 does not exist" >&2
  exit 1
fi

SVCS=$(echo "homelab_services:"; \
  systemctl list-units --type=service | \
  grep "Homelab: " | \
  sed -r 's/^.\s*([a-zA-Z0-9_-]+)\.service.*$/  - \1/')

echo "$SVCS" | jinjanate --quiet --format=yaml -o "$file" "$file.j2"

echo "Rendered the file $file"
