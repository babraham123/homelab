#!/usr/bin/env bash
# Extracts sudo commands from the dispatcher scripts. Outputs as yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/parse_dispatcher.sh HOST

set -euo pipefail

host=$1
file="src/${host}/dispatcher.sh"
if [ ! -f "$file" ]; then
  echo "error: dispatcher file for $host does not exist" >&2
  exit 1
fi

echo "${host}_sudo_cmds:"
# Extract lines starting with "sudo", isolate the command and arguments, 
# sort them alphabetically, and format as YAML lists.
sed -nE 's/^[[:space:]]*sudo[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+).*$/\1 \2/p' "$file" | \
  sort | uniq | {
    last_cmd=""
    while read -r cmd arg; do
      if [ "$cmd" != "$last_cmd" ]; then
        echo "  - $cmd"
        last_cmd="$cmd"
      fi
      if [ -n "$arg" ]; then
        echo "    - $arg"
      fi
    done
  }

echo "\n${host}_commands:"
sed -nE 's/^[[:space:]]+([a-zA-Z0-9_]+)\).*$/\1/p' "$file" | \
  while read -r cmd; do
  echo "  - $cmd"
done