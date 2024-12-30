#!/usr/bin/env bash
# Extracts unique subdomains from the *svcs traefik routing config. Outputs as yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/parse_routes.sh HOST

set -euo pipefail

host=$1
file="src/${host}/traefik/routes.yml"
if [ ! -f "$file" ]; then
  echo "error: route file for $host does not exist" >&2
  exit 1
fi

echo "${host}_subdomains:"
yq '.http.routers | to_entries | .[].value.rule' "$file" | \
  sed -r 's/^.*Host\(`([^.]+)\..*$/  - \1/' | sort | uniq
