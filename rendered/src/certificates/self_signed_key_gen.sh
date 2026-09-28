#!/bin/bash
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
openssl genrsa -out private/wildcard.janedoe.com.key.pem 2048
chmod 400 private/wildcard.janedoe.com.key.pem

openssl genrsa -out private/ldap.janedoe.com.key.pem 2048
chmod 400 private/ldap.janedoe.com.key.pem
scp private/ldap.janedoe.com.key.pem autoadmin@secsvcs:/home/autoadmin

openssl genrsa -out private/auth.janedoe.com.key.pem 2048
chmod 400 private/auth.janedoe.com.key.pem
scp private/auth.janedoe.com.key.pem autoadmin@secsvcs:/home/autoadmin

openssl genrsa -out private/pgdb.janedoe.com.key.pem 2048
chmod 400 private/pgdb.janedoe.com.key.pem
scp private/pgdb.janedoe.com.key.pem autoadmin@secsvcs:/home/autoadmin

openssl genrsa -out private/secproxy.janedoe.com.key.pem 2048
chmod 400 private/secproxy.janedoe.com.key.pem
scp private/secproxy.janedoe.com.key.pem autoadmin@secsvcs:/home/autoadmin

openssl genrsa -out private/webproxy.janedoe.com.key.pem 2048
chmod 400 private/webproxy.janedoe.com.key.pem
scp private/webproxy.janedoe.com.key.pem autoadmin@websvcs:/home/autoadmin

openssl genrsa -out private/homeproxy.janedoe.com.key.pem 2048
chmod 400 private/homeproxy.janedoe.com.key.pem
scp private/homeproxy.janedoe.com.key.pem autoadmin@homesvcs:/home/autoadmin

openssl genrsa -out private/mqtt.janedoe.com.key.pem 2048
chmod 400 private/mqtt.janedoe.com.key.pem
scp private/mqtt.janedoe.com.key.pem autoadmin@homesvcs:/home/autoadmin

openssl genrsa -out private/zigbee.janedoe.com.key.pem 2048
chmod 400 private/zigbee.janedoe.com.key.pem
scp private/zigbee.janedoe.com.key.pem autoadmin@homesvcs:/home/autoadmin

openssl genrsa -out private/home.janedoe.com.key.pem 2048
chmod 400 private/home.janedoe.com.key.pem
scp private/home.janedoe.com.key.pem autoadmin@homesvcs:/home/autoadmin

ssh autoadmin@secsvcs "install_keys"
ssh autoadmin@websvcs "install_keys"
ssh autoadmin@homesvcs "install_keys"

date -u > /root/ca/date_self_signed_keys.txt
echo -e '\nMake sure to run self_signed_cert_gen.sh next'
