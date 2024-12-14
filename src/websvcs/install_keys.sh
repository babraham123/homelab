#!/usr/bin/env bash
# Moves the SSL keys into their respective locations. websvcs only.
# Usage:
#   src/websvcs/install_keys.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv webproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key

rm -rf ./*.pem
