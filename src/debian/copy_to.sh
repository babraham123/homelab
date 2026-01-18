#!/usr/bin/env bash
# Copy a file to a remote host.
# Usage:
#   /root/homelab-rendered/src/debian/copy_to.sh SUBDOMAIN FILENAME REMOTE_FILEPATH
set -euo pipefail

host="$1"
addr="manualadmin@$host.{{ site.url }}"
file="$2"
temp="/home/manualadmin/$(basename "$file")"
path="$3"

scp "$file" "$addr:$temp"
ssh -t "$addr" 'sudo mv '"$temp"' '"$path"''
