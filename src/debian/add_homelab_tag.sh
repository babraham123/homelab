#!/usr/bin/env bash
# src/debian/add_homelab_tag.sh SYSTEMD_FILE.service
# Prefix service description with "Homelab: "

if grep -q "Description=\"Homelab: " "$1"; then
  exit 0
fi

sed -ri'' 's/^Description=["'\'']?([^"'\'']*)["'\'']?$/Description="Homelab: \1"/' "$1"
