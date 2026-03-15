#!/usr/bin/env bash
# Find all tags associated with a given docker image tag.
# Usage:
#   /root/homelab-rendered/src/pve1/lookup_docker_tag.sh REPO TAG

set -euo pipefail

repo="$1"
tag="$2"

# Get a better rate limit
skopeo login docker.io

digest=$(skopeo inspect --format='{{ .Digest }}' "docker://docker.io/${repo}:${tag}")
echo "${repo}:${tag} has the following corresponding tags:"

# Loop through each tag to get its digest
while IFS= read -r tag_i; do
  digest_i=$(skopeo inspect --format '{{ .Digest }}' "docker://docker.io/${repo}:${tag_i}")
  if [[ "$digest_i" == "$digest" ]]; then
    printf '%s\n' "$tag_i"
  fi
done <<EOF
$(skopeo list-tags "docker://docker.io/${repo}" | jq -r '.Tags[]' | grep -v "sha256-" | tac)
EOF
