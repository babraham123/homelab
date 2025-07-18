#!/usr/bin/env bash
# Detects the current Wi-Fi network and switches the network location accordingly.
# Only runs on macOS.
# Usage:
#   /usr/local/bin/detect_wifi_change.sh
#   Normally run automatically by a MacOS LaunchAgent.

set -euo pipefail

iface=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
ssid=$(ipconfig getsummary "$iface" | grep -w SSID | awk '{print $NF}')

if [[ $ssid == "{{ wifi.ssid24 }}" || $ssid == "{{ wifi.ssid5 }}" ]]
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
