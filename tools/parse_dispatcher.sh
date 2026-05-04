#!/usr/bin/env bash
# Extracts sudo commands from the dispatcher scripts. Outputs as yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/parse_dispatcher.sh HOST

set -euo pipefail

host=$1
file="src/${host}/dispatcher.sh"
if [[ "$host" == "gaming" ]]; then
  file="src/gaming/Dispatcher.ps1"
fi

if [ ! -f "$file" ]; then
  echo "error: dispatcher file for $host does not exist" >&2
  exit 1
fi

if [[ "$host" == "gaming" ]]; then
  echo "\ngaming_commands:"
  sed -nE 's/^[[:space:]]+"([a-zA-Z0-9_]+)"[[:space:]]\{.*$/\1/p' "$file" | \
    while read -r cmd; do
      echo "  - ${cmd}"
    done
  exit 0
fi

echo "${host}_sudo_cmds:"
# Extract lines starting with "sudo", isolate the command
sed -nE 's/^[[:space:]]*sudo[[:space:]]+(.+)$/\1/p' "$file" | \
  sort | uniq | while read -r cmd; do
    echo "  - ${cmd}"
  done

echo "\n${host}_commands:"
sed -nE 's/^[[:space:]]+([a-zA-Z0-9_]+)\).*$/\1/p' "$file" | \
  while read -r cmd; do
    echo "  - ${cmd}"
  done