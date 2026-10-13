# PVE1 setup specific for hosting secsvcs
Initial setup for the primary VM host, PVE1. Handles the self signed CA and other certificates,
secrets management, notifications and VM management services.

- Make sure that [Proxmox setup](./proxmox.md) has been completed.
- Create the secsvcs and homesvcs VMs (websvcs is on [PVE2](./pve2.md)). Configure podman on them.
- PVE1 is where some maintenance actions occur, like refreshing TLS certs.

## Configs
- Install tools
```bash
sudo su
cd /root
pip3 install --break-system-packages jinjanator jinjanator-plugin-ansible passlib "bcrypt==4.0.1"

# Install yq
YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" -O - | tar xz
mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
rm yq* install-man-page.sh
```

## SSH Certificates

### CA certs
[Ref](https://free-pmx.org/guides/ssh-certs/)
- Generate the CA keys. They should be kept as secure as possible.
```bash
mkdir -p /root/ssh/public
cd /root/ssh
chmod 700 public

# Include passphrase, remember it
ssh-keygen -t ed25519 -f ca_ssh_key -C "SSH CA for janedoe.com"
chmod 444 ca_ssh_key.pub
chmod 400 ca_ssh_key

# Leave the passphrase blank
ssh-keygen -t ed25519 -f ca_ssh_host_key -C "SSH Host CA for janedoe.com"
chmod 444 ca_ssh_host_key.pub
chmod 400 ca_ssh_host_key

# root's client key, signed by ssh_cert_gen.sh as manualadmin/autoadmin.
# No passphrase: pve1's scripts SSH to the other hosts with it unprompted.
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""

```
- Wait until all of the VMs have been created, then bootstrap trust in the CA. `ssh_cert_gen.sh`
  runs every host's `install_ssh_ca` through the dispatcher, which accepts only a certificate login
  with key ID `pve1`: root needs a certificate, and each host needs the CA's public key, before the
  script can install anything. Asks for `manualadmin`'s password on each host. Same block for a new
  CA ([Nothing escrowed](./pve1_recovery.md#nothing-escrowed)): hosts trust both CAs until the
  script replaces the file
```bash
cd /root/ssh
ssh-keygen -s ca_ssh_key -I pve1 -n manualadmin,autoadmin -V +395d /root/.ssh/id_ed25519.pub
# vpnsvcs's SSH port; install_ssh_ca installs the same file later
install -m 644 /root/homelab-rendered/src/base/debian/ssh_config /etc/ssh/ssh_config.d/homelab.conf
tee -a /etc/ssh/ca_ssh_key.pub < ca_ssh_key.pub > /dev/null
for host in devtop homesvcs pve2 secsvcs vpnsvcs websvcs; do
  scp ca_ssh_key.pub "manualadmin@${host}:"
  ssh -t "manualadmin@${host}" 'sudo tee -a /etc/ssh/ca_ssh_key.pub < ca_ssh_key.pub > /dev/null && rm ca_ssh_key.pub'
done
```
- Sign and distribute everything
```bash
/root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen.sh
# The cert for the gaming VM will be generated later
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
# Fill in all of the secrets you can based on `src/nodes/pve1/secrets_template.yaml`
sops /root/secrets/pve1.yaml
```

- Generate the SOPS/AGE secsvcs secrets file
```bash
scp manualadmin@secsvcs:/home/manualadmin/.ssh/id_ed25519.pub secsvcs_id_ed25519.pub
chmod 400 secsvcs_id_ed25519.pub
# Fill in all of the secrets you can based on `src/nodes/secsvcs/secrets_template.yaml`
/root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs
```

- Generate the SOPS/AGE websvcs secrets file
```bash
scp manualadmin@websvcs:/home/manualadmin/.ssh/id_ed25519.pub websvcs_id_ed25519.pub
chmod 400 websvcs_id_ed25519.pub
# Fill in all of the secrets you can based on `src/nodes/websvcs/secrets_template.yaml`
/root/homelab-rendered/src/nodes/pve1/secret_update.sh websvcs
```

- Generate the SOPS/AGE homesvcs secrets file
```bash
scp manualadmin@homesvcs:/home/manualadmin/.ssh/id_ed25519.pub homesvcs_id_ed25519.pub
chmod 400 homesvcs_id_ed25519.pub
# Fill in all of the secrets you can based on `src/nodes/homesvcs/secrets_template.yaml`
/root/homelab-rendered/src/nodes/pve1/secret_update.sh homesvcs
```

## Self-Signed Certificates
Use self-signed certs for server to server traffic. Use Let's Encrypt certs for user facing sites.

### CA infra
[Ref](https://jamielinux.com/docs/openssl-certificate-authority/index.html)
- Setup CA infrastructure for self signed certs. The root CA key should be kept as secure as
  possible.
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

# vpnsvcs's SSH port comes from the ssh_config that ssh_cert_gen.sh installed on pve1
function upload() { /root/homelab-rendered/src/base/debian/send_files.sh intermediate/certs/ca-chain.cert.pem | ssh "autoadmin@${1}" install_ca; }
upload pve1
upload pve2
upload vpnsvcs
upload secsvcs
upload homesvcs
upload websvcs
upload devtop
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
- Create domain specific keys and certs
```bash
# Wait until the services in secsvcs, websvcs and homesvcs are setup but not yet started
/root/homelab-rendered/src/nodes/pve1/certificates/self_signed_key_gen.sh
/root/homelab-rendered/src/nodes/pve1/certificates/self_signed_cert_gen.sh
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
# Wait until the services in secsvcs, websvcs and homesvcs are started
/root/homelab-rendered/src/nodes/pve1/certificates/acme_transfer.sh
```

## Notifications
- Create a custom Gmail account
- Enable 2 Step verification
- Generate app passwords for lldap, authelia and msmtp,
  [Ref](https://support.google.com/accounts/answer/185833?hl=en)
```bash
# Update sops files
/root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs
sops /root/secrets/pve1.yaml
```
- Setup notifications
```bash
# Enable AppArmor
apt install -y msmtp msmtp-mta
vim /etc/apparmor.d/usr.bin.msmtp +82
```
```
/usr/bin/hostname PUx,
/root/homelab-rendered/src/nodes/pve1/msmtp_password.sh PUx,
```
- Install the notifier
```bash
apparmor_parser -r /etc/apparmor.d/usr.bin.msmtp
cd /root/homelab-rendered
cp src/base/debian/msmtprc /etc
src/nodes/pve1/install_svcs.sh cert_notifier
```

## Backups
- Install the weekly backup. First add the `pbs2` storage and the client key from the [Proxmox
  guide](./proxmox.md#backups).
```bash
cd /root/homelab-rendered
src/nodes/pve1/install_svcs.sh backup_orchestrator
```
