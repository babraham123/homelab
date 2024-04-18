#!/usr/bin/env bash
# src/secsvcs/install_certs.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv auth.{{ site.url }}.cert.pem /etc/opt/authelia/certificates/auth.cert.pem
mv ldap.{{ site.url }}.cert.pem /etc/opt/lldap/certificates/ldap.cert.pem
cp /etc/opt/lldap/certificates/ldap.cert.pem /etc/opt/authelia/certificates

mv pgdb.{{ site.url }}.cert.pem /etc/opt/db/certificates/pgdb.crt
chown 70:70 /etc/opt/db/certificates/*.crt
# https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

mv secproxy.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/secproxy.crt
mv secproxy.{{ site.url }}.client_cert.pem /etc/opt/traefik/certificates/secproxy.client.crt
cp /etc/opt/traefik/certificates/secproxy.client.crt /etc/opt/authelia/certificates/secproxy.client.pem

mv webproxy.{{ site.url }}.client_cert.pem /etc/opt/authelia/certificates/webproxy.client.pem
mv ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt

cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/authelia/certificates/ca.chain.pem
cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/lldap/certificates/ca.chain.pem
cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/db/certificates/ca.chain.crt
cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/gatus/certificates/ca.chain.pem
cp /etc/opt/traefik/certificates/ca.chain.crt /etc/opt/grafana/certificates/ca.chain.pem

mv wildcard.{{ site.url }}.cert.pem /etc/opt/traefik/certificates/wildcard.crt

rm -rf ./*.pem
