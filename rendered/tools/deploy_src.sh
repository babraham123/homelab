#!/bin/bash
# Renders the source code and copies it to the homelab servers.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/deploy_src.sh

set -euo pipefail

# A private (0700) parent dir; upload_src.sh needs the name homelab-rendered
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT
project_dir="${render_dir}/homelab-rendered"
tools/render_src.sh "$project_dir"

tools/upload_src.sh pve1 "$project_dir" || echo "pve1 upload failed"
tools/upload_src.sh secsvcs "$project_dir" || echo "secsvcs upload failed"
tools/upload_src.sh homesvcs "$project_dir" || echo "homesvcs upload failed"
tools/upload_src.sh pve2 "$project_dir" || echo "pve2 upload failed"
tools/upload_src.sh websvcs "$project_dir" || echo "websvcs upload failed"
tools/upload_src.sh vpnsvcs "$project_dir" || echo "vpnsvcs upload failed"
tools/upload_src.sh router "$project_dir" || echo "router upload failed"
tools/upload_src.sh devtop "$project_dir" || echo "devtop upload failed"

echo -e "\nStart the gaming VM and run the following cmd:"
echo "tools/upload_src.sh gaming \"$project_dir\""
