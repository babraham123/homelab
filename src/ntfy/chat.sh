#!/usr/bin/env bash
# Sends a push notification to all users.
# Usage:
#   /root/homelab-rendered/src/ntfy/chat.sh TITLE SUBJECT [PRIORITY]

set -euo pipefail

title="$1"
subject="$2"
priority="${3:-3}"
password=$(/root/homelab-rendered/src/podman/get_secret.sh "ntfy_person_password")
hash=$(echo "person:$password" | base64)
curl -X POST \
  -H "Authorization: Basic $hash" \
  -H "X-Title: $title" \
  -H "X-Priority: $priority" \
  -d "$subject" https://push.{{ site.url }}/chat
