#!/usr/bin/env bash
# Moves the certificates into their respective locations. homesvcs only.
# Usage:
#   src/homesvcs/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv homeproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/proxy.crt
mv homeproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt

rm -rf ./*.pem
