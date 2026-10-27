# shellcheck shell=bash
# Sourced first by every tools/*.sh. The workstation counterpart of src/base/lib.sh,
# which assumes a node.
#   # shellcheck source=tools/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

# Prints the template data: the YAML vars on stdin, then the node inventory under DIR
# (DIR/<node>/inventory.yml) as one mapping under `nodes:`, in node-name order, then the
# lists tools/inventory.py derives from both as `inv:`. jinjanate takes one data file, so
# the render and the tests both build it here. Usage: template_vars src/nodes < vars.yml
template_vars() {
  local vars inv inventory
  vars=$(
    cat
    echo
    echo "nodes:"
    for inventory in "$1"/*/inventory.yml; do
      echo "  $(basename "$(dirname "$inventory")"):"
      sed 's/^/    /' "$inventory"
    done
  )
  inv=$(printf '%s\n' "$vars" | "$(dirname "${BASH_SOURCE[0]}")/inventory.py" derive) || return
  printf '%s\ninv: %s\n' "$vars" "$inv"
}
