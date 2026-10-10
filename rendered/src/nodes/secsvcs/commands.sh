#!/bin/bash
# Usage:
#   src/nodes/secsvcs/commands.sh CMD

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# The install_* commands take their files on stdin, bundled by send_files.sh.
case $1 in
  install_certs)
    receive_files auth.janedoe.com.cert.pem ldap.janedoe.com.cert.pem pgdb.janedoe.com.cert.pem \
      secproxy.janedoe.com.cert.pem secproxy.janedoe.com.client_cert.pem \
      webproxy.janedoe.com.client_cert.pem homeproxy.janedoe.com.client_cert.pem ca-chain.cert.pem
    mkdir -p /etc/opt/authelia/certificates
    mkdir -p /etc/opt/lldap/certificates
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/db/certificates
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /etc/opt/grafana/certificates

    mv auth.janedoe.com.cert.pem /etc/opt/authelia/certificates/auth.cert.pem
    mv ldap.janedoe.com.cert.pem /etc/opt/lldap/certificates/ldap.cert.pem
    cp /etc/opt/lldap/certificates/ldap.cert.pem /etc/opt/authelia/certificates

    mv pgdb.janedoe.com.cert.pem /etc/opt/db/certificates/pgdb.crt
    chown 70:70 /etc/opt/db/certificates/*.crt
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

    mv secproxy.janedoe.com.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv secproxy.janedoe.com.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt
    cp /etc/opt/traefik/certificates/proxy.client.crt /etc/opt/authelia/certificates/secproxy.client.pem

    mv webproxy.janedoe.com.client_cert.pem /etc/opt/authelia/certificates/webproxy.client.pem
    mv homeproxy.janedoe.com.client_cert.pem /etc/opt/authelia/certificates/homeproxy.client.pem
    
    cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/authelia/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/lldap/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/db/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/gatus/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/grafana/certificates/ca.chain.pem
    ;;
  install_keys)
    receive_files auth.janedoe.com.key.pem ldap.janedoe.com.key.pem secproxy.janedoe.com.key.pem \
      pgdb.janedoe.com.key.pem
    mkdir -p /etc/opt/authelia/certificates
    mkdir -p /etc/opt/lldap/certificates
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/db/certificates

    mv auth.janedoe.com.key.pem /etc/opt/authelia/certificates/auth.key
    mv ldap.janedoe.com.key.pem /etc/opt/lldap/certificates/ldap.key.pem

    mv secproxy.janedoe.com.key.pem /etc/opt/traefik/certificates/proxy.key

    mv pgdb.janedoe.com.key.pem /etc/opt/db/certificates/pgdb.key
    chown 70:70 /etc/opt/db/certificates/pgdb.key
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile
    ;;
  install_olive_tin_cert)
    receive_files id_ed25519 id_ed25519.pub id_ed25519-cert.pub known_hosts
    mkdir -p /etc/opt/olive_tin/ssh
    mv ./id_ed25519* /etc/opt/olive_tin/ssh
    mv ./known_hosts /etc/opt/olive_tin/ssh
    chmod 644 /etc/opt/olive_tin/ssh/known_hosts
    ;;
  *)
    die "unknown file type: $1"
    ;;
esac
