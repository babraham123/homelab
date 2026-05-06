#!/bin/bash
# Extracts services from install_svcs.sh for dispatcher.sh.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/gen_dispatch_cmds.sh HOST

set -euo pipefail

host=$1
file="src/${host}/install_svcs.sh"
if [ ! -f "$file" ]; then
  echo "error: install file for $host does not exist" >&2
  exit 1
fi

sed -nE 's/^[[:space:]]+([a-zA-Z0-9_]+)\).*$/\1/p' "$file" | \
  while read -r cmd; do
  echo "  install_${cmd})"
  echo "    sudo /root/homelab-rendered/${file} ${cmd}"
  echo "    ;;"
done

echo "  install_all_svcs)"
sed -nE 's/^[[:space:]]+([a-zA-Z0-9_]+)\).*$/\1/p' "$file" | \
  while read -r cmd; do
  echo "    sudo /root/homelab-rendered/${file} ${cmd}"
done
echo "    ;;"
echo "  *)"
