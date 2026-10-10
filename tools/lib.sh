# shellcheck shell=bash
# Sourced first by every tools/*.sh. The workstation counterpart of src/base/lib.sh,
# which assumes a node.
#   # shellcheck source=tools/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }
