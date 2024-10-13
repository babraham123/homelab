#!/usr/bin/env bash
# Extracts unique subdomains from the secsvcs traefik routing config. Outputs as yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/parse_secsvcs_routes.sh src/secsvcs/traefik/routes.yml

set -euo pipefail

echo "secsvcs_subdomains:"
yq '.http.routers | to_entries | .[].value.rule' "$1" | \
  sed -r 's/^.*Host\(`([^.]+)\..*$/  - \1/' | sort | uniq
