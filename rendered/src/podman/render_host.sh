#!/bin/bash
# Renders the given file in the same directory as it's template (FILENAME.j2).
# Includes basic networking details about the host.
# Usage:
#   src/podman/render_host.sh SUBDOMAIN FILENAME
# Ref:
# https://github.com/kpfleming/jinjanator

set -euo pipefail

file=$2
rm -f "$file"

if [ ! -f "$file.j2" ]; then
  echo "error: file template $file.j2 does not exist" >&2
  exit 1
fi

case $1 in
  secsvcs)
    subnet="10.10.0"
    ;;
  websvcs)
    subnet="10.11.0"
    ;;
  homesvcs)
    subnet="10.12.0"
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

echo "subnet: $subnet" | jinjanate --quiet --format=yaml -o "$file" "$file.j2"
