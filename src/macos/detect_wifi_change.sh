#!/usr/bin/env bash
# /usr/local/bin/detect_wifi_change.sh

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
