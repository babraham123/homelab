#!/bin/bash
# Usage:
#   src/nodes/websvcs/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

cd /home/autoadmin

case $1 in
  install_certs)
    # Move the certificates into their respective locations.
    chown root:root ./*.pem
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/guacamole/certs

    mv webproxy.janedoe.com.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv webproxy.janedoe.com.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

    cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/guacamole/certs/ca.chain.pem

    rm -rf ./*.pem
    ;;
  install_keys)
    # Move the SSL keys into their respective locations.
    chown root:root ./*.pem
    mkdir -p /etc/opt/traefik/certificates

    mv webproxy.janedoe.com.key.pem /etc/opt/traefik/certificates/proxy.key

    rm -rf ./*.pem
    ;;
  *)
    die "unknown file type: $1"
    ;;
esac
