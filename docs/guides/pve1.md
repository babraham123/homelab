# PVE1 setup specific for hosting secsvcs
Initial setup for the primary VM host, PVE1. Handles the self signed CA and other certificates, secrets management, notifications and VM management services.

- Make sure that [Proxmox setup](./proxmox.md) has been completed.
- Create the secsvcs VM with the desired resources and devices attached. secsvcs holds a select group of services that have higher security and uptime requirements. All services are containerized.
- PVE1 is the location of all user initiated actions, such as updating service configs or refreshing TLS certs.

## Configs
- Get access
```bash
sudo su
ssh-copy-id admin@router.{{ site.url }}
ssh-copy-id {{ username }}@pve2.{{ site.url }}
ssh-copy-id {{ username }}@secsvcs.{{ site.url }}
ssh-copy-id {{ username }}@websvcs.{{ site.url }}
ssh-copy-id {{ username }}@vpn.{{ site.url }}
```

- Install tools
```bash
cd /root
apt install -y fd-find python3-pip git yamllint
pip3 install --break-system-packages jinjanator jinjanator-plugin-ansible passlib

# Install yq
YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" -O - | tar xz
mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
rm yq* install-man-page.sh
```

- Render source
```bash
git clone {{ repo }} homelab
cd /root/homelab
# Fill in personal details based on vars.template.yml
vim vars.yml
tools/update_src.sh
```

## Secrets
- Generate the AGE keys
```bash
apt install -y age curl moreutils jq

# Install SOPS
SOPS_VERSION=$(curl -s "https://api.github.com/repos/getsops/sops/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
curl -Lo sops.deb "https://github.com/getsops/sops/releases/latest/download/sops_${SOPS_VERSION}_amd64.deb"
apt --fix-broken install ./sops.deb
rm -rf sops.deb
echo -e '\nexport SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub)' >> ~/.zshrc
echo -e 'export SOPS_AGE_KEY_FILE="/root/secrets/age.txt"' >> ~/.zshrc
source ~/.zshrc
echo -e '\nexport SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub)' >> ~/.bashrc
echo -e 'export SOPS_AGE_KEY_FILE="/root/secrets/age.txt"' >> ~/.bashrc

mkdir /root/secrets
chmod 700 /root/secrets
cd /root/secrets
age-keygen -o age.txt
age-keygen -y age.txt > age.pub
chmod 400 age.*
```

- Generate the SOPS pve1 secrets file
```bash
# Fill in all of the secrets you can based on `src/pve1/secrets_template.yaml`
sops /root/secrets/pve1.yaml
```

- Generate the SOPS/AGE secsvcs secrets file
```bash
scp {{ username }}@secsvcs.{{ site.url }}:/home/{{ username }}/.ssh/id_ed25519.pub secsvcs_id_ed25519.pub
chmod 400 secsvcs_id_ed25519.pub
ssh -t {{ username }}@secsvcs.{{ site.url }} 'sudo mkdir -p /etc/opt/secrets'
# Fill in all of the secrets you can based on `src/secsvcs/secrets_template.yaml`
/root/homelab-rendered/src/secsvcs/secret_update.sh
```

- Generate the SOPS/AGE websvcs secrets file
```bash
scp {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}/.ssh/id_ed25519.pub websvcs_id_ed25519.pub
chmod 400 websvcs_id_ed25519.pub
ssh -t {{ username }}@websvcs.{{ site.url }} 'sudo mkdir -p /etc/opt/secrets'
# Fill in all of the secrets you can based on `src/websvcs/secrets_template.yaml`
/root/homelab-rendered/src/websvcs/secret_update.sh
```

## Self-Signed Certificates
Use self-signed certs for server to server traffic. Use Let's Encrypt certs for user facing sites.

### CA infra
[Ref](https://jamielinux.com/docs/openssl-certificate-authority/index.html)
- Setup CA infrastructure for self signed certs. The root CA key should be kept as secure as possible. 
```bash
# root CA
mkdir /root/ca
cd /root/ca
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
vim /root/ca/openssl.cnf
# include passphrase, remember it
openssl genrsa -aes256 -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem
openssl req -config openssl.cnf \
  -key private/ca.key.pem \
  -new -x509 -days 7300 -sha256 -extensions v3_ca \
  -out certs/ca.cert.pem
chmod 444 certs/ca.cert.pem
# confirm cert
openssl x509 -noout -text -in certs/ca.cert.pem

# intermediate CA
mkdir /root/ca/intermediate
cd /root/ca/intermediate
mkdir certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > /root/ca/intermediate/crlnumber
vim /root/ca/intermediate/openssl.cnf
# include passphrase, remember it
openssl genrsa -aes256 -out private/intermediate.key.pem 4096
chmod 400 private/intermediate.key.pem
openssl req -config openssl.cnf -new -sha256 \
  -key private/intermediate.key.pem \
  -out csr/intermediate.csr.pem
cd /root/ca
openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
  -days 3650 -notext -md sha256 \
  -in intermediate/csr/intermediate.csr.pem \
  -out intermediate/certs/intermediate.cert.pem
chmod 444 intermediate/certs/intermediate.cert.pem
# confirm cert and DB entry
cat index.txt
openssl x509 -noout -text -in intermediate/certs/intermediate.cert.pem
openssl verify -CAfile certs/ca.cert.pem intermediate/certs/intermediate.cert.pem

# copy and create a CA certificate chain
cat intermediate/certs/intermediate.cert.pem certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem
chmod 444 intermediate/certs/ca-chain.cert.pem

scp intermediate/certs/ca-chain.cert.pem {{ username }}@vpn.{{ site.url }}:/home/{{ username }}/{{ site.url }}.ca_chain.cert.pem
ssh -t {{ username }}@vpn.{{ site.url }} 'sudo mv /home/{{ username }}/{{ site.url }}.ca_chain.cert.pem /etc/ssl/certs'
scp intermediate/certs/ca-chain.cert.pem {{ username }}@websvcs.{{ site.url }}:/home/{{ username }}/{{ site.url }}.ca_chain.cert.pem
ssh -t {{ username }}@websvcs.{{ site.url }} 'sudo mv /home/{{ username }}/{{ site.url }}.ca_chain.cert.pem /etc/ssl/certs'
```

- Example cert, normally done via gen script
```bash
openssl genrsa -out intermediate/private/www.example.com.key.pem 2048
chmod 400 intermediate/private/www.example.com.key.pem
openssl req -config intermediate/openssl.cnf \
  -key intermediate/private/www.example.com.key.pem \
  -addext 'subjectAltName = DNS:www.example.com' \
  -new -sha256 -out intermediate/csr/www.example.com.csr.pem
openssl ca -config intermediate/openssl.cnf \
  -extensions server_cert -days 365 -notext -md sha256 \
  -in intermediate/csr/www.example.com.csr.pem \
  -out intermediate/certs/www.example.com.cert.pem
chmod 444 intermediate/certs/www.example.com.cert.pem
openssl verify -CAfile intermediate/certs/ca-chain.cert.pem intermediate/certs/www.example.com.cert.pem
```

### Manage certs
- Create keys
```bash
# Wait until the services in VPN and websvcs are setup but not yet started
/root/homelab-rendered/src/certificates/self_signed_key_gen.sh
/root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
```

## ACME Certificates

### Transfer certs from Traefik
- Copy job
```bash
mkdir /root/acme
cd /root/acme
TCD_VERSION=$(curl -s "https://api.github.com/repos/ldez/traefik-certs-dumper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/ldez/traefik-certs-dumper/releases/download/v${TCD_VERSION}/traefik-certs-dumper_v${TCD_VERSION}_linux_amd64.tar.gz" -O - | tar xz
mv traefik-certs-dumper /usr/local/bin/traefik-certs-dumper
# Wait until the services in VPN and websvcs are started
/root/homelab-rendered/src/certificates/acme_transfer.sh
```

## SMTP
- Create a custom Gmail account
- Enable 2 Step verification
- Generate app passwords for lldap, authelia and msmtp, [Ref](https://support.google.com/accounts/answer/185833?hl=en)
```bash
# Update sops files
/root/homelab-rendered/src/secsvcs/secret_update.sh
sops /root/secrets/pve1.yaml
```
- Setup cert notifications
```bash
# Enable AppArmor
apt install -y msmtp msmtp-mta
# Update AppArmor profile, add "/usr/local/bin/msmtp_password.sh PUx,"
vim /etc/apparmor.d/usr.bin.msmtp +82
apparmor_parser -r /etc/apparmor.d/usr.bin.msmtp

cd /root/homelab-rendered
cp src/pve1/msmtp_password.sh /usr/local/bin
cp src/certificates/msmtprc /etc
src/debian/install_svcs.sh cert_notifier
```

## VM management
[Docs](https://pve.proxmox.com/pve-docs/qm.1.html)

- Watchdog to prevent stuck VM
```bash
src/debian/install_svcs.sh vm_watchdog
```
