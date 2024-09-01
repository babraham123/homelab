#!/usr/bin/env bash
# Moves the SSL keys into their respective locations. Websvcs only.
# Usage:
#   src/websvcs/install_keys.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv webproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key
mv wildcard.{{ site.url }}.key.pem /etc/opt/traefik/certificates/wildcard.key

rm -rf ./*.pem
