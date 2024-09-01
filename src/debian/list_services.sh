#!/usr/bin/env bash
# Prints out all systemd services with the "Homelab: " prefix.
# Usage:
#   /usr/local/bin/list_services.sh

set -euo pipefail

systemctl list-units --type=service | \
  grep "Homelab: " | \
  sed -r 's/^.\s*([a-zA-Z0-9_-]+)\.service.*$/\1/'
