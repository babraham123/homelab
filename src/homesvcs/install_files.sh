#!/usr/bin/env bash
# Usage:
#   src/homesvcs/install_files.sh TYPE
# type = certs
# Moves the certificates into their respective locations. homesvcs only.
# type = keys
# Moves the SSL keys into their respective locations. homesvcs only.

set -euo pipefail

cd /home/admin

case $1 in
  certs)
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
    ;;
  keys)
    chown root:root ./*.pem

    mv homeproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key

    mv mqtt.{{ site.url }}.key.pem /etc/opt/mosquitto/certificates/key.pem

    mv zigbee.{{ site.url }}.key.pem /etc/opt/zigbee2mqtt/certificates/client.key

    rm -rf ./*.pem
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
