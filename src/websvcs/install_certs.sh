#!/usr/bin/env bash
# src/websvcs/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv webproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/webproxy.crt
mv webproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/webproxy.client.crt

mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
mv wildcard.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/wildcard.crt

rm -rf ./*.pem
