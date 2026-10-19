#!/bin/bash
# Renders the source code and copies it to the homelab servers.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/deploy_src.sh

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A private (0700) parent dir; upload_src.sh needs the name homelab-rendered
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT
project_dir="${render_dir}/homelab-rendered"
tools/render_src.sh "$project_dir"

# The repo plus vars.yml, the one render input that isn't in git, to pve1's
# /root/backups/repo. ssh encrypts it in flight; pve1 already holds every secret.
{ git ls-files -z; printf 'vars.yml\0'; } | tar --null -T - -czf - | \
  ssh autoadmin@pve1 archive_repo || echo "pve1 repo archive failed"

for dir in src/nodes/*/; do
  node=$(basename "$dir")
  # The gaming VM is usually off, so its upload is left to the user, below
  [[ $node == gaming ]] && continue
  tools/upload_src.sh "$node" "$project_dir" || echo "${node} upload failed"
done

# The render above is deleted on exit, so the user renders again
cat <<'EOF'

Start the gaming VM and run the following cmds:
out=$(mktemp -d)/homelab-rendered
tools/render_src.sh "$out" && tools/upload_src.sh gaming "$out"
EOF
