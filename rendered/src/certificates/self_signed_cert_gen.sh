#!/bin/bash
# Generate self-signed certificates and distribute them to the secsvcs, websvcs and homesvcs servers.
# Usage:
#   /root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
set -euo pipefail

# site.name is free text: backslash-escaped for -subj, where / and + separate fields,
# then shell-quoted once here rather than inside each -subj.
org='JD'"'"'s System'
subj="/C=US/ST=California/L=Middletown/O=${org}"

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh secsvcs
/root/homelab-rendered/src/debian/is_reachable.sh websvcs
/root/homelab-rendered/src/debian/is_reachable.sh homesvcs

cd /root/ca/intermediate
# Ref: https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html#:~:text=fc%20%2De%20%2D.-,read,-%5B%20%2DrszpqAclneE%20%5D%20%5B
echo -n 'Enter intermediate CA passphrase: '
read -r -s CA_PASS

openssl req -config openssl.cnf \
  -key private/wildcard.janedoe.com.key.pem \
  -subj "${subj}/OU=svcs/CN=*.janedoe.com" \
  -addext 'subjectAltName = DNS:*.janedoe.com,DNS:janedoe.com' \
  -new -sha256 -out csr/wildcard.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/wildcard.janedoe.com.csr.pem \
  -out certs/wildcard.janedoe.com.cert.pem
chmod 444 certs/wildcard.janedoe.com.cert.pem

openssl req -config openssl.cnf \
  -key private/ldap.janedoe.com.key.pem \
  -subj "${subj}/OU=secsvcs/CN=ldap.janedoe.com" \
  -addext 'subjectAltName = DNS:ldap.janedoe.com' \
  -new -sha256 -out csr/ldap.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/ldap.janedoe.com.csr.pem \
  -out certs/ldap.janedoe.com.cert.pem
chmod 444 certs/ldap.janedoe.com.cert.pem
scp certs/ldap.janedoe.com.cert.pem autoadmin@secsvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/auth.janedoe.com.key.pem \
  -subj "${subj}/OU=secsvcs/CN=auth.janedoe.com" \
  -addext 'subjectAltName = DNS:auth.janedoe.com' \
  -new -sha256 -out csr/auth.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/auth.janedoe.com.csr.pem \
  -out certs/auth.janedoe.com.cert.pem
chmod 444 certs/auth.janedoe.com.cert.pem
scp certs/auth.janedoe.com.cert.pem autoadmin@secsvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/pgdb.janedoe.com.key.pem \
  -subj "${subj}/OU=secsvcs/CN=pgdb.janedoe.com" \
  -addext 'subjectAltName = DNS:pgdb.janedoe.com' \
  -new -sha256 -out csr/pgdb.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/pgdb.janedoe.com.csr.pem \
  -out certs/pgdb.janedoe.com.cert.pem
chmod 444 certs/pgdb.janedoe.com.cert.pem
scp certs/pgdb.janedoe.com.cert.pem autoadmin@secsvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/secproxy.janedoe.com.key.pem \
  -subj "${subj}/OU=secsvcs/CN=secproxy.janedoe.com" \
  -addext 'subjectAltName = DNS:secproxy.janedoe.com' \
  -new -sha256 -out csr/secproxy.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/secproxy.janedoe.com.csr.pem \
  -out certs/secproxy.janedoe.com.cert.pem
chmod 444 certs/secproxy.janedoe.com.cert.pem
scp certs/secproxy.janedoe.com.cert.pem autoadmin@secsvcs:/home/autoadmin
scp certs/ca-chain.cert.pem autoadmin@secsvcs:/home/autoadmin

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/secproxy.janedoe.com.csr.pem \
  -out certs/secproxy.janedoe.com.client_cert.pem
chmod 444 certs/secproxy.janedoe.com.client_cert.pem
scp certs/secproxy.janedoe.com.client_cert.pem autoadmin@secsvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/webproxy.janedoe.com.key.pem \
  -subj "${subj}/OU=websvcs/CN=webproxy.janedoe.com" \
  -addext 'subjectAltName = DNS:webproxy.janedoe.com' \
  -new -sha256 -out csr/webproxy.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/webproxy.janedoe.com.csr.pem \
  -out certs/webproxy.janedoe.com.cert.pem
chmod 444 certs/webproxy.janedoe.com.cert.pem
scp certs/webproxy.janedoe.com.cert.pem autoadmin@websvcs:/home/autoadmin
scp certs/ca-chain.cert.pem autoadmin@websvcs:/home/autoadmin

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/webproxy.janedoe.com.csr.pem \
  -out certs/webproxy.janedoe.com.client_cert.pem
chmod 444 certs/webproxy.janedoe.com.client_cert.pem
scp certs/webproxy.janedoe.com.client_cert.pem autoadmin@secsvcs:/home/autoadmin
scp certs/webproxy.janedoe.com.client_cert.pem autoadmin@websvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/homeproxy.janedoe.com.key.pem \
  -subj "${subj}/OU=homesvcs/CN=homeproxy.janedoe.com" \
  -addext 'subjectAltName = DNS:homeproxy.janedoe.com' \
  -new -sha256 -out csr/homeproxy.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/homeproxy.janedoe.com.csr.pem \
  -out certs/homeproxy.janedoe.com.cert.pem
chmod 444 certs/homeproxy.janedoe.com.cert.pem
scp certs/homeproxy.janedoe.com.cert.pem autoadmin@homesvcs:/home/autoadmin
scp certs/ca-chain.cert.pem autoadmin@homesvcs:/home/autoadmin

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/homeproxy.janedoe.com.csr.pem \
  -out certs/homeproxy.janedoe.com.client_cert.pem
chmod 444 certs/homeproxy.janedoe.com.client_cert.pem
scp certs/homeproxy.janedoe.com.client_cert.pem autoadmin@secsvcs:/home/autoadmin
scp certs/homeproxy.janedoe.com.client_cert.pem autoadmin@homesvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/mqtt.janedoe.com.key.pem \
  -subj "${subj}/OU=homesvcs/CN=mqtt.janedoe.com" \
  -addext 'subjectAltName = DNS:mqtt.janedoe.com' \
  -new -sha256 -out csr/mqtt.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/mqtt.janedoe.com.csr.pem \
  -out certs/mqtt.janedoe.com.cert.pem
chmod 444 certs/mqtt.janedoe.com.cert.pem
scp certs/mqtt.janedoe.com.cert.pem autoadmin@homesvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/zigbee.janedoe.com.key.pem \
  -subj "${subj}/OU=homesvcs/CN=zigbee.janedoe.com" \
  -addext 'subjectAltName = DNS:zigbee.janedoe.com' \
  -new -sha256 -out csr/zigbee.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/zigbee.janedoe.com.csr.pem \
  -out certs/zigbee.janedoe.com.client_cert.pem
chmod 444 certs/zigbee.janedoe.com.client_cert.pem
scp certs/zigbee.janedoe.com.client_cert.pem autoadmin@homesvcs:/home/autoadmin

openssl req -config openssl.cnf \
  -key private/home.janedoe.com.key.pem \
  -subj "${subj}/OU=homesvcs/CN=home.janedoe.com" \
  -addext 'subjectAltName = DNS:home.janedoe.com' \
  -new -sha256 -out csr/home.janedoe.com.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/home.janedoe.com.csr.pem \
  -out certs/home.janedoe.com.client_cert.pem
chmod 444 certs/home.janedoe.com.client_cert.pem
scp certs/home.janedoe.com.client_cert.pem autoadmin@homesvcs:/home/autoadmin

ssh autoadmin@secsvcs "install_certs"
ssh autoadmin@websvcs "install_certs"
ssh autoadmin@homesvcs "install_certs"

date -u > /root/ca/date_self_signed_certs.txt
echo -e '\nMake sure to restart all secure services'
