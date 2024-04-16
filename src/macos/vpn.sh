#!/usr/bin/env bash
# /usr/local/bin/vpn.sh

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
    echo "Unknown cmd: $1"
    exit 1
    ;;
esac
