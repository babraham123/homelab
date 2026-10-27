#!/bin/bash
# Runs VictoriaMetrics' or VictoriaLogs' MCP server over stdio for Claude Code
# (docs/guides/claude_telemetry.md). The admin password is read from the macOS Keychain at
# launch, so it never sits in a Claude config file. Stdout is the MCP channel: nothing else
# may print to it.
# Usage:
#   tools/mcp_victoria.sh metrics|logs

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

kind=${1:?usage: $0 metrics|logs}
case $kind in
  metrics)
    server=mcp-victoriametrics prefix=VM
    export VM_INSTANCE_TYPE=single
    ;;
  logs)
    server=mcp-victorialogs prefix=VL
    ;;
  *)
    die "unknown kind: $kind (metrics|logs)"
    ;;
esac

# Claude Code starts it from wherever the session began; vars.yml is at the repo root
cd "$(dirname "${BASH_SOURCE[0]}")/.."
url=$(yq --yaml-fix-merge-anchor-to-spec=true ".site.url" vars.yml)
secret="victoria${kind}_admin_password"
pw=$(security find-generic-password -s "$secret" -w) \
  || die "no Keychain entry ${secret}: docs/guides/claude_telemetry.md"

export "${prefix}_INSTANCE_ENTRYPOINT=https://${kind}.${url}"
export "${prefix}_INSTANCE_HEADERS=Authorization=Basic $(printf 'admin:%s' "$pw" | base64)"
# Where docs/guides/claude_telemetry.md installs them, often missing from the PATH Claude Code
# inherits
export PATH="$PATH:$HOME/.local/bin"
exec "$server"
