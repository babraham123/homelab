# 03. Shared bash library sourced by all scripts

Status: ready-for-agent
Type: task
Repo: homelab
Source: user item 54
Blocked by: 02

## Change

`src/base/lib.sh`:

```bash
# shellcheck shell=bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
log()  { printf '%s %s\n' "$(date -Is)" "$*"; }
warn() { log "warning: $*" >&2; }
die()  { log "error: $*" >&2; exit 1; }
require_root()      { [[ $EUID -eq 0 ]] || die "must run as root"; }
is_reachable()      { ping -c1 -W3 "$1" >/dev/null 2>&1; }
require_reachable() { is_reachable "$1" || die "$1 unreachable"; }
# Polls until the host answers; backup-and-dr/01 uses it after start_pve2.
wait_reachable()    { local host=$1 timeout=${2:-300} t=0
                      until is_reachable "$host"; do
                        (( t += 5 )); (( t < timeout )) || die "$host unreachable after ${timeout}s"; sleep 5
                      done; }
rendered=/root/homelab-rendered/src
install_quadlet()   { cp "$@" /etc/containers/systemd/; }
install_files()     { local dst=$1; shift; mkdir -p "$dst"; cp "$@" "$dst"; }
reload_restart()    { systemctl daemon-reload; systemctl restart "$1"; systemctl status "$1" --no-pager; }
```

- Every `install_svcs.sh`, `commands.sh`, `dispatcher.sh`, `secret_update.sh`,
  `vm_watchdog.sh`, `cert_*.sh` starts with
  `source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"` (path per layout in 02).
- Delete `src/base/debian/is_root.sh` and `is_reachable.sh` (subprocess versions);
  replace the common tail of each `install_svcs.sh` with `reload_restart "$1"`. If
  backup-and-dr/01 landed first, switch its `is_reachable.sh` loop to `wait_reachable`.
- Workstation `tools/*.sh` get a sibling `tools/lib.sh` (they don't have
  `/root/homelab-rendered`); keep it tiny.
- `install_svcs.sh`'s `cp podman/*.sh /usr/local/bin` must also copy `lib.sh` since
  `get_secret*.sh` will source it.

## Acceptance

- `grep -L 'source .*lib.sh' src/**/*.sh` returns only the files that intentionally
  don't (e.g. Windows/PowerShell, `probes/`).
- shellcheck clean.

## Comments
