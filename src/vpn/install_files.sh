#!/usr/bin/env bash
# Usage:
#   src/vpn/install_files.sh TYPE
# type = repo
# Installs the rendered repo source. VPN only.

set -euo pipefail

cd /home/manualadmin

case $1 in
  repo)
    chown -R root:root homelab-rendered
    mv homelab-rendered /root
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
