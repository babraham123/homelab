# shellcheck shell=bash
# Sourced first by every script that runs on a Debian or PVE node. Scripts that run in
# place from the rendered tree source it relative to themselves:
#   # shellcheck source=src/base/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# Copies installed outside the tree (install_bin, the dispatcher, node_exporter's runner)
# source the copy install_lib puts in /usr/local/lib/homelab, readable by any user:
#   source /usr/local/lib/homelab/lib.sh
# PATH is left alone: scripts that pin it export it after sourcing; the rest need the
# caller's, e.g. render_*.sh run jinjanate from /usr/local/bin. Scripts that run without
# some of these options turn them back off after sourcing.

set -euo pipefail

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

# Usage: receive_files NAME...; for a command that takes files on stdin, bundled by
# src/base/debian/send_files.sh. Extracts the stream into a private temp dir, which must
# then hold exactly NAME... and SHA256SUMS, all regular files, every NAME listed in the
# manifest and matching it; then cds there, so the caller moves the files by name. The
# dir is removed when the script exits.
receive_files() {
  local dir found expected listed
  dir=$(mktemp -d)
  # shellcheck disable=SC2064 # expanded now on purpose: dir is local
  trap "rm -rf '${dir}'" EXIT
  tar -C "$dir" -x --no-same-owner
  expected=$(printf '%s\n' SHA256SUMS "$@" | sort)
  found=$(cd "$dir" && find . -mindepth 1 | sed 's|^\./||' | sort)
  [[ $found == "$expected" ]] || die "received '$(tr '\n' ' ' <<< "$found")', expected exactly: SHA256SUMS $*"
  [[ -z $(find "$dir" -mindepth 1 ! -type f) ]] || die "received something that isn't a regular file"
  listed=$(sed 's/^[0-9a-f]\{64\}  //' "${dir}/SHA256SUMS" | sort)
  [[ $listed == "$(printf '%s\n' "$@" | sort)" ]] || die "SHA256SUMS doesn't list exactly: $*"
  (cd "$dir" && sha256sum -c --quiet --strict SHA256SUMS)
  cd "$dir"
}

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
# Prints the services described "Homelab: …", one per line without .service. --all keeps
# the inactive ones, like a timer's oneshot between runs.
homelab_services() {
  systemctl list-units --all --type=service --plain --no-legend |
    awk '/Homelab: / { sub(/\.service$/, "", $1); print $1 }' | sort -u
}
