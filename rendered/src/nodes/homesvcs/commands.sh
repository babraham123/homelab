#!/bin/bash
# Usage:
#   src/nodes/homesvcs/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# The install_* commands take their files on stdin, bundled by send_files.sh.
case $1 in
  install_certs)
    receive_files homeproxy.janedoe.com.cert.pem homeproxy.janedoe.com.client_cert.pem mqtt.janedoe.com.cert.pem \
      zigbee.janedoe.com.client_cert.pem home.janedoe.com.client_cert.pem ca-chain.cert.pem
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
    ;;
  install_keys)
    receive_files homeproxy.janedoe.com.key.pem mqtt.janedoe.com.key.pem zigbee.janedoe.com.key.pem \
      home.janedoe.com.key.pem
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
    ;;
  *)
    die "unknown file type: $1"
    ;;
esac
