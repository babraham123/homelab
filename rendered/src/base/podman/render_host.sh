#!/bin/bash
# Renders the given file in the same directory as it's template (FILENAME.j2).
# Includes basic networking details about the host.
# Usage:
#   src/base/podman/render_host.sh SUBDOMAIN FILENAME
# Ref:
# https://github.com/kpfleming/jinjanator

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

file=$2
rm -f "$file"

if [ ! -f "$file.j2" ]; then
  die "file template $file.j2 does not exist"
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
  vpnsvcs)
    subnet="10.13.0"
    ;;
  *)
    die "unknown service: $1"
    ;;
esac

echo "subnet: $subnet" | jinjanate --quiet --format=yaml -o "$file" "$file.j2"
