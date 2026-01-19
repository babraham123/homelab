#!/usr/bin/env bash
# Extracts internal urls from the gatus uptime config. Outputs as yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/parse_uptime_urls.sh src/gatus/config.yaml

set -euo pipefail

echo "uptime_internal_urls:" > /tmp/parsed.yml
yq --yaml-fix-merge-anchor-to-spec=true \
  '.endpoints[] | select(.group == "internal") | .url' "$1" | \
  sed 's/^/  - /' | sort | uniq >> /tmp/parsed.yml

jinjanate --quiet /tmp/parsed.yml vars.yml
rm -f /tmp/parsed.yml
