#!/usr/bin/env bash
# Generate SSL keys and distribute them to the secsvcs, websvcs and homesvcs servers.
# Usage:
#   /root/homelab-rendered/src/certificates/self_signed_key_gen.sh
set -euo pipefail

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh secsvcs
/root/homelab-rendered/src/debian/is_reachable.sh websvcs
/root/homelab-rendered/src/debian/is_reachable.sh homesvcs

cd /root/ca/intermediate

# Generate keys
openssl genrsa -out private/wildcard.{{ site.url }}.key.pem 2048
chmod 400 private/wildcard.{{ site.url }}.key.pem

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

openssl genrsa -out private/homeproxy.{{ site.url }}.key.pem 2048
chmod 400 private/homeproxy.{{ site.url }}.key.pem
scp private/homeproxy.{{ site.url }}.key.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/mqtt.{{ site.url }}.key.pem 2048
chmod 400 private/mqtt.{{ site.url }}.key.pem
scp private/mqtt.{{ site.url }}.key.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

openssl genrsa -out private/zigbee.{{ site.url }}.key.pem 2048
chmod 400 private/zigbee.{{ site.url }}.key.pem
scp private/zigbee.{{ site.url }}.key.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

echo "secsvcs server password:"
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/secsvcs/install_keys.sh'

echo "websvcs server password:"
ssh -t {{ username }}@websvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/websvcs/install_keys.sh'

echo "homesvcs server password:"
ssh -t {{ username }}@homesvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/homesvcs/install_keys.sh'

date -u > /root/ca/date_self_signed_keys.txt
echo -e '\nMake sure to run self_signed_cert_gen.sh next'
