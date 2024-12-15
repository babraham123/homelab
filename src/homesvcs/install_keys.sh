#!/usr/bin/env bash
# Moves the SSL keys into their respective locations. Websvcs only.
# Usage:
#   src/homesvcs/install_keys.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv homeproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key

rm -rf ./*.pem
