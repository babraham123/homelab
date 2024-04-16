#!/usr/bin/env bash
# /usr/local/bin/self_signed_key_gen.sh
set -euo pipefail

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

cd /root/ca/intermediate

# Generate keys
openssl genrsa -out private/wildcard.{{ site.url }}.key.pem 2048
chmod 400 private/wildcard.{{ site.url }}.key.pem
scp private/wildcard.{{ site.url }}.key.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}
scp private/wildcard.{{ site.url }}.key.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/ldap.{{ site.url }}.key.pem 2048
chmod 400 private/ldap.{{ site.url }}.key.pem
scp private/ldap.{{ site.url }}.key.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/auth.{{ site.url }}.key.pem 2048
chmod 400 private/auth.{{ site.url }}.key.pem
scp private/auth.{{ site.url }}.key.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/pgdb.{{ site.url }}.key.pem 2048
chmod 400 private/pgdb.{{ site.url }}.key.pem
scp private/pgdb.{{ site.url }}.key.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/secproxy.{{ site.url }}.key.pem 2048
chmod 400 private/secproxy.{{ site.url }}.key.pem
scp private/secproxy.{{ site.url }}.key.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/webproxy.{{ site.url }}.key.pem 2048
chmod 400 private/webproxy.{{ site.url }}.key.pem
scp private/webproxy.{{ site.url }}.key.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}

echo "secsvcs server password:"
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/secsvcs/install_keys.sh'

echo "websvcs server password:"
ssh -t {{ username }}@websvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/websvcs/install_keys.sh'

date -u > /root/ca/date_self_signed_keys.txt
echo -e '\nMake sure to run self_signed_cert_gen.sh next'
