#!/usr/bin/env bash
# Checks if the given server is reachable.
# Usage:
#   /root/homelab-rendered/src/debian/is_reachable.sh SUBDOMAIN
set -euo pipefail

subdomain=$1
if ! ping -c3 -W3 "$subdomain.{{ site.url }}"; then
  echo "$subdomain is not reachable."
  exit 1
fi
