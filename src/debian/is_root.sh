#!/usr/bin/env bash
# Checks if the current user is root.
# Usage:
#   /root/homelab-rendered/src/debian/is_root.sh
set -euo pipefail

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi
