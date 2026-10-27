#!/bin/bash
# Renders the source code and copies it to the homelab servers.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/deploy_src.sh            # every node but gaming
#   tools/deploy_src.sh NODE...    # only these; gaming too, if it's on

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Checked before rendering, so a typo fails fast
for node in "$@"; do
  [[ -d src/nodes/$node ]] || die "no node ${node} (src/nodes/)"
done

# A private (0700) parent dir; upload_src.sh needs the name homelab-rendered
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT
project_dir="${render_dir}/homelab-rendered"
tools/render_src.sh "$project_dir"

# The repo plus vars.yml, the one render input that isn't in git, to pve1's
# /root/backups/repo. ssh encrypts it in flight; pve1 already holds every secret.
{ git ls-files -z; printf 'vars.yml\0'; } | tar --null -T - -czf - | \
  ssh autoadmin@pve1 archive_repo || echo "pve1 repo archive failed"

nodes=("$@")
if (( ! $# )); then
  for dir in src/nodes/*/; do
    node=$(basename "$dir")
    # The gaming VM is usually off, so its upload is left to the user, below
    [[ $node == gaming ]] || nodes+=("$node")
  done
fi
for node in "${nodes[@]}"; do
  tools/upload_src.sh "$node" "$project_dir" || echo "${node} upload failed"
done

(( $# )) || cat <<'EOF'

Start the gaming VM and run:
tools/deploy_src.sh gaming
EOF
