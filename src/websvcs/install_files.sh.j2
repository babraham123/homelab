#!/usr/bin/env bash
# Usage:
#   src/websvcs/install_files.sh TYPE
# type = certs
# Moves the certificates into their respective locations. websvcs only.
# type = keys
# Moves the SSL keys into their respective locations. websvcs only.

set -euo pipefail

cd /home/manualadmin

case $1 in
  certs)
    chown root:root ./*.pem

    mv webproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv webproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt

    mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt

    rm -rf ./*.pem
    ;;  
  keys)
    chown root:root ./*.pem

    mv webproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key

    rm -rf ./*.pem
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
