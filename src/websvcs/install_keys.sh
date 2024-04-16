#!/usr/bin/env bash
# src/websvcs/install_keys.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv webproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/webproxy.key
mv wildcard.{{ site.url }}.key.pem /etc/opt/traefik/certificates/wildcard.key

rm -rf ./*.pem
