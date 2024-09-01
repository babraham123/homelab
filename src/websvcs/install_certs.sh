#!/usr/bin/env bash
# Moves the certificates into their respective locations. Websvcs only.
# Usage:
#   src/websvcs/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv webproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/proxy.crt
mv webproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
mv wildcard.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/wildcard.crt

rm -rf ./*.pem
