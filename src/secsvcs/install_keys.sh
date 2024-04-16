#!/usr/bin/env bash
# src/secsvcs/install_keys.sh

set -euo pipefail

cd /home/{{ username }}
chown root:root ./*.pem

mv auth.{{ site.url }}.key.pem /etc/opt/authelia/certificates/auth.key
mv ldap.{{ site.url }}.key.pem /etc/opt/lldap/certificates/ldap.key.pem

mv secproxy.{{ site.url }}.key.pem /etc/opt/traefik/certificates/secproxy.key
mv wildcard.{{ site.url }}.key.pem /etc/opt/traefik/certificates/wildcard.key

mv pgdb.{{ site.url }}.key.pem /etc/opt/db/certificates/pgdb.key
chown 70:70 /etc/opt/db/certificates/pgdb.key
# https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

rm -rf ./*.pem
