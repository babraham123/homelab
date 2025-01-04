#!/usr/bin/env bash
# Usage:
#   src/secsvcs/install_files.sh TYPE
# type = certs
# Moves the certificates to their respective directories. secsvcs only.
# type = keys
# Moves the SSL keys into their respective locations. secsvcs only.

set -euo pipefail

cd /home/{{ username }}

case $1 in
  certs)
    chown root:root ./*.pem

    mv auth.{{ site.url }}.cert.pem /etc/opt/authelia/certificates/auth.cert.pem
    mv ldap.{{ site.url }}.cert.pem /etc/opt/lldap/certificates/ldap.cert.pem
    cp /etc/opt/lldap/certificates/ldap.cert.pem /etc/opt/authelia/certificates

    mv pgdb.{{ site.url }}.cert.pem /etc/opt/db/certificates/pgdb.crt
    chown 70:70 /etc/opt/db/certificates/*.crt
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

    mv secproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv secproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt
    cp /etc/opt/traefik/certificates/proxy.client.crt /etc/opt/authelia/certificates/secproxy.client.pem

    mv webproxy.{{ site.url }}.client_cert.pem /etc/opt/authelia/certificates/webproxy.client.pem
    mv homeproxy.{{ site.url }}.client_cert.pem /etc/opt/authelia/certificates/homeproxy.client.pem
    mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt

    cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/authelia/certificates/ca.chain.pem
    cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/lldap/certificates/ca.chain.pem
    cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/db/certificates/ca.chain.crt
    cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/gatus/certificates/ca.chain.pem
    cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/grafana/certificates/ca.chain.pem

    rm -rf ./*.pem
    ;;
  keys)
    chown root:root ./*.pem

    mv auth.{{ site.url }}.key.pem /etc/opt/authelia/certificates/auth.key
    mv ldap.{{ site.url }}.key.pem /etc/opt/lldap/certificates/ldap.key.pem

    mv secproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/proxy.key

    mv pgdb.{{ site.url }}.key.pem /etc/opt/db/certificates/pgdb.key
    chown 70:70 /etc/opt/db/certificates/pgdb.key
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

    rm -rf ./*.pem
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
