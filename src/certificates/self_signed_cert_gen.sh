#!/usr/bin/env bash
# Generate self-signed certificates and distribute them to the secsvcs, websvcs and homesvcs servers.
# Usage:
#   /root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
set -euo pipefail

/root/homelab-rendered/src/debian/is_root.sh
/root/homelab-rendered/src/debian/is_reachable.sh secsvcs
/root/homelab-rendered/src/debian/is_reachable.sh websvcs
/root/homelab-rendered/src/debian/is_reachable.sh homesvcs

cd /root/ca/intermediate
# Ref: https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html#:~:text=fc%20%2De%20%2D.-,read,-%5B%20%2DrszpqAclneE%20%5D%20%5B
echo -n 'Enter intermediate CA passphrase: '
read -r -s CA_PASS

openssl req -config openssl.cnf \
  -key private/wildcard.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=svcs/CN=*.{{ site.url }}' \
  -addext 'subjectAltName = DNS:*.{{ site.url }},DNS:{{ site.url }}' \
  -new -sha256 -out csr/wildcard.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/wildcard.{{ site.url }}.csr.pem \
  -out certs/wildcard.{{ site.url }}.cert.pem
chmod 444 certs/wildcard.{{ site.url }}.cert.pem

openssl req -config openssl.cnf \
  -key private/ldap.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=secsvcs/CN=ldap.{{ site.url }}' \
  -addext 'subjectAltName = DNS:ldap.{{ site.url }}' \
  -new -sha256 -out csr/ldap.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/ldap.{{ site.url }}.csr.pem \
  -out certs/ldap.{{ site.url }}.cert.pem
chmod 444 certs/ldap.{{ site.url }}.cert.pem
scp certs/ldap.{{ site.url }}.cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/auth.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=secsvcs/CN=auth.{{ site.url }}' \
  -addext 'subjectAltName = DNS:auth.{{ site.url }}' \
  -new -sha256 -out csr/auth.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/auth.{{ site.url }}.csr.pem \
  -out certs/auth.{{ site.url }}.cert.pem
chmod 444 certs/auth.{{ site.url }}.cert.pem
scp certs/auth.{{ site.url }}.cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/pgdb.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=secsvcs/CN=pgdb.{{ site.url }}' \
  -addext 'subjectAltName = DNS:pgdb.{{ site.url }}' \
  -new -sha256 -out csr/pgdb.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/pgdb.{{ site.url }}.csr.pem \
  -out certs/pgdb.{{ site.url }}.cert.pem
chmod 444 certs/pgdb.{{ site.url }}.cert.pem
scp certs/pgdb.{{ site.url }}.cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/secproxy.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=secsvcs/CN=secproxy.{{ site.url }}' \
  -addext 'subjectAltName = DNS:secproxy.{{ site.url }}' \
  -new -sha256 -out csr/secproxy.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/secproxy.{{ site.url }}.csr.pem \
  -out certs/secproxy.{{ site.url }}.cert.pem
chmod 444 certs/secproxy.{{ site.url }}.cert.pem
scp certs/secproxy.{{ site.url }}.cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}
scp certs/ca-chain.cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/secproxy.{{ site.url }}.csr.pem \
  -out certs/secproxy.{{ site.url }}.client_cert.pem
chmod 444 certs/secproxy.{{ site.url }}.client_cert.pem
scp certs/secproxy.{{ site.url }}.client_cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/webproxy.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=websvcs/CN=webproxy.{{ site.url }}' \
  -addext 'subjectAltName = DNS:webproxy.{{ site.url }}' \
  -new -sha256 -out csr/webproxy.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/webproxy.{{ site.url }}.csr.pem \
  -out certs/webproxy.{{ site.url }}.cert.pem
chmod 444 certs/webproxy.{{ site.url }}.cert.pem
scp certs/webproxy.{{ site.url }}.cert.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}
scp certs/ca-chain.cert.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/webproxy.{{ site.url }}.csr.pem \
  -out certs/webproxy.{{ site.url }}.client_cert.pem
chmod 444 certs/webproxy.{{ site.url }}.client_cert.pem
scp certs/webproxy.{{ site.url }}.client_cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}
scp certs/webproxy.{{ site.url }}.client_cert.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/homeproxy.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=homesvcs/CN=homeproxy.{{ site.url }}' \
  -addext 'subjectAltName = DNS:homeproxy.{{ site.url }}' \
  -new -sha256 -out csr/homeproxy.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/homeproxy.{{ site.url }}.csr.pem \
  -out certs/homeproxy.{{ site.url }}.cert.pem
chmod 444 certs/homeproxy.{{ site.url }}.cert.pem
scp certs/homeproxy.{{ site.url }}.cert.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}
scp certs/ca-chain.cert.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/homeproxy.{{ site.url }}.csr.pem \
  -out certs/homeproxy.{{ site.url }}.client_cert.pem
chmod 444 certs/homeproxy.{{ site.url }}.client_cert.pem
scp certs/homeproxy.{{ site.url }}.client_cert.pem {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}
scp certs/homeproxy.{{ site.url }}.client_cert.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/mqtt.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=homesvcs/CN=mqtt.{{ site.url }}' \
  -addext 'subjectAltName = DNS:mqtt.{{ site.url }}' \
  -new -sha256 -out csr/mqtt.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions server_cert -days 395 -notext -md sha256 \
  -in csr/mqtt.{{ site.url }}.csr.pem \
  -out certs/mqtt.{{ site.url }}.cert.pem
chmod 444 certs/mqtt.{{ site.url }}.cert.pem
scp certs/mqtt.{{ site.url }}.cert.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

openssl req -config openssl.cnf \
  -key private/zigbee.{{ site.url }}.key.pem \
  -subj '/C={{ personal.country_code }}/ST={{ personal.state }}/L={{ personal.city }}/O={{ site.name }}/OU=homesvcs/CN=zigbee.{{ site.url }}' \
  -addext 'subjectAltName = DNS:zigbee.{{ site.url }}' \
  -new -sha256 -out csr/zigbee.{{ site.url }}.csr.pem
openssl ca -config openssl.cnf -passin "pass:$CA_PASS" \
  -extensions usr_cert -days 395 -notext -md sha256 \
  -in csr/zigbee.{{ site.url }}.csr.pem \
  -out certs/zigbee.{{ site.url }}.client_cert.pem
chmod 444 certs/zigbee.{{ site.url }}.client_cert.pem
scp certs/zigbee.{{ site.url }}.client_cert.pem {{ username }}@homesvcs.{{ site.url }}:/home/{{ username }}

echo "secsvcs root password:"
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/secsvcs/install_files.sh certs'

echo "websvcs root password:"
ssh -t {{ username }}@websvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/websvcs/install_files.sh certs'

echo "homesvcs root password:"
ssh -t {{ username }}@homesvcs.{{ site.url }} 'sudo /root/homelab-rendered/src/homesvcs/install_files.sh certs'

date -u > /root/ca/date_self_signed_certs.txt
echo -e '\nMake sure to restart all secure services'
