# shellcheck shell=bash
# Sourced first by every script that runs on a Debian or PVE node. Scripts that run in
# place from the rendered tree source it relative to themselves:
#   # shellcheck source=src/base/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# Copies installed outside the tree (install_bin, the dispatcher, node_exporter's runner)
# source the copy install_lib puts in /usr/local/lib/homelab, readable by any user:
#   source /usr/local/lib/homelab/lib.sh

set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

rendered=/root/homelab-rendered/src

log()  { printf '%s %s\n' "$(date -Is)" "$*"; }
warn() { log "warning: $*" >&2; }
die()  { log "error: $*" >&2; exit 1; }

require_root() { (( EUID == 0 )) || die "must run as root"; }

is_reachable() { ping -c3 -W3 "$1" &> /dev/null; }
# Usage: require_reachable HOST...
require_reachable() {
  local host
  for host in "$@"; do
    is_reachable "$host" || die "${host} unreachable"
  done
}

# Usage: wait_for TIMEOUT_S ERROR_MSG CMD...; polls CMD until it succeeds
wait_for() {
  local timeout=$1 msg=$2 t=0
  shift 2
  until "$@" &> /dev/null; do
    (( t += 5 ))
    (( t < timeout )) || die "${msg} after ${timeout}s"
    sleep 5
  done
}
# Usage: wait_reachable HOST [TIMEOUT_S]
wait_reachable() { wait_for "${2:-300}" "$1 unreachable" is_reachable "$1"; }

install_lib() { install -D -m 644 "${rendered}/base/lib.sh" /usr/local/lib/homelab/lib.sh; }
# Usage: install_bin SCRIPT...; for scripts run from /usr/local/bin, which source the
# installed library
install_bin() {
  install_lib
  install -D -t /usr/local/bin "$@"
}
install_quadlet() { install -D -m 644 -t /etc/containers/systemd "$@"; }
reload_restart() {
  systemctl daemon-reload
  systemctl restart "$1"
  systemctl status "$1" --no-pager
}
