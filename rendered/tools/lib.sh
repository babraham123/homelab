# shellcheck shell=bash
# Sourced first by every tools/*.sh. The workstation counterpart of src/base/lib.sh,
# which assumes a node.
#   # shellcheck source=tools/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

# Prints the node inventory under DIR (DIR/<node>/inventory.yml) as one YAML mapping
# under `nodes:`, in node-name order. Usage: node_inventory src/nodes
node_inventory() {
  local inventory
  echo "nodes:"
  for inventory in "$1"/*/inventory.yml; do
    echo "  $(basename "$(dirname "$inventory")"):"
    sed 's/^/    /' "$inventory"
  done
}
