#!/bin/bash
# Usage:
#   src/homesvcs/commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/autoadmin

case $1 in
  install_certs)
    # Move the certificates into their respective locations.
    chown root:root ./*.pem
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/mosquitto/certificates
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    mkdir -p /etc/opt/home_assistant/certs

    mv homeproxy.janedoe.com.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv homeproxy.janedoe.com.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

    mv mqtt.janedoe.com.cert.pem /etc/opt/mosquitto/certificates/server.pem

    mv zigbee.janedoe.com.client_cert.pem /etc/opt/zigbee2mqtt/certificates/client.crt

    mv home.janedoe.com.client_cert.pem /etc/opt/home_assistant/certs/client.pem

    cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/mosquitto/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/zigbee2mqtt/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/home_assistant/certs/ca.chain.pem

    rm -rf ./*.pem
    ;;
  install_keys)
    # Move the SSL keys into their respective locations.
    chown root:root ./*.pem
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/mosquitto/certificates
    mkdir -p /etc/opt/zigbee2mqtt/certificates
    mkdir -p /etc/opt/home_assistant/certs

    mv homeproxy.janedoe.com.key.pem /etc/opt/traefik/certificates/proxy.key

    mv mqtt.janedoe.com.key.pem /etc/opt/mosquitto/certificates/key.pem
    # mosquitto drops root and runs as uid 1883 before loading the key.
    # https://github.com/eclipse-mosquitto/mosquitto/blob/master/docker/2.0-openssl/Dockerfile
    chown 1883:1883 /etc/opt/mosquitto/certificates/key.pem

    mv zigbee.janedoe.com.key.pem /etc/opt/zigbee2mqtt/certificates/client.key

    mv home.janedoe.com.key.pem /etc/opt/home_assistant/certs/client.key

    rm -rf ./*.pem
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
