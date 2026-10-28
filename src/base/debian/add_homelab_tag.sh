#!/bin/bash
# Prefixes the service's description with "Homelab: ": a unit file about to be installed, or
# an installed unit by name, wherever its package put the file (/usr/lib or /etc/systemd/system)
# Usage:
#   src/base/debian/add_homelab_tag.sh PATH/UNIT.service
#   src/base/debian/add_homelab_tag.sh UNIT.service

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

if [[ -f $1 ]]; then
  file=$1
else
  file=$(systemctl show -P FragmentPath "$1")
  [[ -n $file ]] || die "$1: no unit file"
fi
if grep -q "Description=\"Homelab: " "$file"; then
  exit 0
fi

sed -ri'' 's/^Description=["'\'']?([^"'\'']*)["'\'']?$/Description="Homelab: \1"/' "$file"
