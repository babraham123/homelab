#!/usr/bin/env bash
# Renders the source code and copies it to the homelab servers.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/deploy_src.sh

set -euo pipefail

project_dir=/tmp/homelab-rendered
tools/render_src.sh "$project_dir"

tools/upload_src.sh pve1 "$project_dir" || true
tools/upload_src.sh secsvcs "$project_dir" || true
tools/upload_src.sh homesvcs "$project_dir" || true
tools/upload_src.sh pve2 "$project_dir" || true
tools/upload_src.sh websvcs "$project_dir" || true
tools/upload_src.sh vpn "$project_dir" || true

rm -rf "$project_dir"
