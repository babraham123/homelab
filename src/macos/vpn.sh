#!/usr/bin/env bash
# Turns the Tailscale VPN on or off and updates the network location accordingly.
# Usage:
#   /usr/local/bin/vpn.sh [up / down]

set -euo pipefail

tailscale=/Applications/Tailscale.app/Contents/MacOS/Tailscale

case $1 in
  up)
    $tailscale status &>/dev/null || $tailscale login
    $tailscale switch {{ site.url }}
    networksetup -switchtolocation Home > /dev/null
    ;;
  down)
    $tailscale logout
    networksetup -switchtolocation Automatic > /dev/null
    ;;
  *)
    echo "error: unknown cmd: $1" >&2
    exit 1
    ;;
esac
