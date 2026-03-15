#!/usr/bin/env bash
# Sends a push notification to all users.
# Usage:
#   /root/homelab-rendered/src/ntfy/chat.sh TITLE MESSAGE [PRIORITY]

set -euo pipefail

title="$1"
msg="$2"
priority="${3:-3}"
password=$(/root/homelab-rendered/src/podman/get_secret.sh "ntfy_person_password")
hash=$(echo -n "person:$password" | base64)
curl -X POST \
  -H "Authorization: Basic $hash" \
  -H "X-Title: $title" \
  -H "X-Priority: $priority" \
  -d "$msg" https://push.{{ site.url }}/chat
