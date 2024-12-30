#!/usr/bin/env bash
# Moves the certificates into their respective locations. homesvcs only.
# Usage:
#   src/homesvcs/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv homeproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/proxy.crt
mv homeproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

mv mqtt.{{ site.url }}.cert.pem /etc/opt/mosquitto/certificates/server.pem

mv zigbee.{{ site.url }}.client_cert.pem /etc/opt/zigbee2mqtt/certificates/client.crt

cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
cp ca-chain.cert.pem /etc/opt/mosquitto/certificates/ca.chain.pem
cp ca-chain.cert.pem /etc/opt/zigbee2mqtt/certificates/ca.chain.crt
mv ca-chain.cert.pem /etc/opt/home_assistant/certs/ca.chain.pem

rm -rf ./*.pem
