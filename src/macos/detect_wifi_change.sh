#!/usr/bin/env bash
# Detects the current Wi-Fi network and switches the network location accordingly.
# Only runs on macOS.
# Usage:
#   /usr/local/bin/detect_wifi_change.sh

set -euo pipefail

if [[ $(networksetup -getairportnetwork en0) == "Current Wi-Fi Network: {{ wifi.ssid24 }}" || $(networksetup -getairportnetwork en0) == "Current Wi-Fi Network: {{ wifi.ssid5 }}" ]]
then
  if ! [[ $(networksetup -getcurrentlocation) == "Home" ]]
  then
    networksetup -switchtolocation Home > /dev/null
    # say "Switched to Home network location"
  fi
else
  if ! [[ $(networksetup -getcurrentlocation) == "Automatic" ]]
  then
    networksetup -switchtolocation Automatic > /dev/null
    # say "Switched to Automatic network location"
  fi
fi
