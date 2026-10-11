#!/bin/bash
# Generate SSL keys and distribute them to the secsvcs, websvcs and homesvcs servers.
# Usage:
#   /root/homelab-rendered/src/base/certificates/self_signed_key_gen.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root
require_reachable secsvcs websvcs homesvcs

send="${rendered}/base/debian/send_files.sh"
cd /root/ca/intermediate

# Generate keys
openssl genrsa -out private/wildcard.janedoe.com.key.pem 2048
chmod 400 private/wildcard.janedoe.com.key.pem

openssl genrsa -out private/ldap.janedoe.com.key.pem 2048
chmod 400 private/ldap.janedoe.com.key.pem

openssl genrsa -out private/auth.janedoe.com.key.pem 2048
chmod 400 private/auth.janedoe.com.key.pem

openssl genrsa -out private/pgdb.janedoe.com.key.pem 2048
chmod 400 private/pgdb.janedoe.com.key.pem

openssl genrsa -out private/secproxy.janedoe.com.key.pem 2048
chmod 400 private/secproxy.janedoe.com.key.pem

openssl genrsa -out private/webproxy.janedoe.com.key.pem 2048
chmod 400 private/webproxy.janedoe.com.key.pem

openssl genrsa -out private/homeproxy.janedoe.com.key.pem 2048
chmod 400 private/homeproxy.janedoe.com.key.pem

openssl genrsa -out private/mqtt.janedoe.com.key.pem 2048
chmod 400 private/mqtt.janedoe.com.key.pem

openssl genrsa -out private/zigbee.janedoe.com.key.pem 2048
chmod 400 private/zigbee.janedoe.com.key.pem

openssl genrsa -out private/home.janedoe.com.key.pem 2048
chmod 400 private/home.janedoe.com.key.pem

openssl genrsa -out private/crowdsec.janedoe.com.key.pem 2048
chmod 400 private/crowdsec.janedoe.com.key.pem

# Each node's files go on its install command's stdin
"$send" \
  private/ldap.janedoe.com.key.pem \
  private/auth.janedoe.com.key.pem \
  private/pgdb.janedoe.com.key.pem \
  private/secproxy.janedoe.com.key.pem \
  private/crowdsec.janedoe.com.key.pem |
  ssh autoadmin@secsvcs install_keys
"$send" private/webproxy.janedoe.com.key.pem | \
  ssh autoadmin@websvcs install_keys
"$send" \
  private/homeproxy.janedoe.com.key.pem \
  private/mqtt.janedoe.com.key.pem \
  private/zigbee.janedoe.com.key.pem \
  private/home.janedoe.com.key.pem |
  ssh autoadmin@homesvcs install_keys

date -u > /root/ca/date_self_signed_keys.txt
echo -e '\nMake sure to run self_signed_cert_gen.sh next'
