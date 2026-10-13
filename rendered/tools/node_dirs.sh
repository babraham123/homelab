#!/bin/bash
# Prints the src/ paths a debian node's rendered tree holds, one per line: all of base/,
# its nodes/<node>/ and each service's `dirs` (default: services/<service>/ if it
# exists). Prints nothing for other nodes, the router and gaming VM, which upload_src.sh
# handles on their own. A debian node is one whose install_dispatcher is
# base/debian/commands.sh's (src/nodes.jinja's debian_nodes).
# upload_src.sh ships only these; check_rendered.py checks they cover every src/ path
# the node's files use.
# Run from the root of the repo or a rendered copy.
# Usage:
#   tools/node_dirs.sh NODE

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

node=$1
inventory="src/nodes/${node}/inventory.yml"
[ -f "$inventory" ] || die "${inventory} doesn't exist"
debian='.commands // [] | any_c(.name == "install_dispatcher" and .script == "base/debian/commands.sh")'
[[ "$(yq "$debian" "$inventory")" == true ]] || exit 0

paths=(base "nodes/${node}")
for path in $(yq '.services // {} | .[] | select(has("dirs")) | .dirs[]' "$inventory"); do
  [ -e "src/${path}" ] || die "${inventory}: src/${path} doesn't exist"
  paths+=("$path")
done
for svc in $(yq '.services // {} | to_entries | .[] | select(.value | has("dirs") | not) | .key' "$inventory"); do
  [ ! -d "src/services/${svc}" ] || paths+=("services/${svc}")
done
printf '%s\n' "${paths[@]}" | sort -u
