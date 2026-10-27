#!/bin/bash
# Usage:
#   src/nodes/websvcs/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# The install_* commands take their files on stdin, bundled by send_files.sh.
case $1 in
  install_certs)
    receive_files webproxy.janedoe.com.cert.pem webproxy.janedoe.com.client_cert.pem \
      appsec-websvcs.janedoe.com.client_cert.pem ca-chain.cert.pem
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/crowdsec_appsec/certificates

    mv webproxy.janedoe.com.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv webproxy.janedoe.com.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt
    mv appsec-websvcs.janedoe.com.client_cert.pem /etc/opt/crowdsec_appsec/certificates/appsec.cert.pem

    cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/crowdsec_appsec/certificates/ca.chain.pem
    ;;
  install_keys)
    receive_files webproxy.janedoe.com.key.pem appsec-websvcs.janedoe.com.key.pem
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/crowdsec_appsec/certificates

    mv webproxy.janedoe.com.key.pem /etc/opt/traefik/certificates/proxy.key
    mv appsec-websvcs.janedoe.com.key.pem /etc/opt/crowdsec_appsec/certificates/appsec.key.pem
    ;;
  *)
    die "unknown file type: $1"
    ;;
esac
