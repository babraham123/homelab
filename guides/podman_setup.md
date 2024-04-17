# Podman setup

- Setup Linux using [debian_setup.md](./debian_setup.md)
- Make sure host setup has been mostly completed, see [vm_host_setup.md](./vm_host_setup.md)
- Review container security measures, for example [ref1](https://www.panoptica.app/research/7-ways-to-escape-a-container)

## Install Podman
- Install dependencies
```bash
sudo apt install -y age jq

YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" -O - | tar xz
sudo mv yq_linux_amd64 /usr/bin/yq
sudo ./install-man-page.sh
rm yq* install-man-page.sh
```
- Install podman: [ref](https://podman.io/docs/installation#linux-distributions)
```bash
# POD_VERSION=$(curl -s "https://api.github.com/repos/containers/podman/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
# wget "https://github.com/containers/podman/releases/download/v${POD_VERSION}/podman-remote-static-linux_amd64.tar.gz"
# tar -vxf podman-remote-static-linux_amd64.tar.gz

curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/Debian_Testing/Release.key \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg > /dev/null
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg]\
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/Debian_Testing/ /" \
  | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list > /dev/null

sudo apt update
sudo apt -y upgrade
sudo apt -y install podman libgpgme11-dev buildah libyajl2
```

## Networking
- Account for conflicts between the podman network and the firewall, [bug](https://stackoverflow.com/questions/70870689/configure-ufw-for-podman-on-port-443)
```bash
sudo ufw allow http
sudo ufw allow https
sudo ufw route allow in on {{ secsvcs.interface }} out on podman1 to any port 80,443 proto tcp
```

- Allow access from container to host
```bash
# scrape node_exporter
# TODO: fix
sudo ufw allow in on {{ secsvcs.interface }} from podman1 to any port 9100 proto tcp
```

## Secrets
- On the VM host, update the SOPS/AGE secrets file if needed
- Configure secrets
```bash
sudo su
# Read secrets from age-encrypted file
mkdir -p /etc/opt/secrets
chmod 700 /etc/opt/secrets
cp /home/{{ username }}/.ssh/id_ed25519* /etc/opt/secrets
chmod 600 /etc/opt/secrets/*
cd /root/homelab-rendered
cp src/podman/secret_lookup.sh /usr/local/bin
cp src/podman/secret_list.sh /usr/local/bin
cp src/podman/containers.conf /etc/containers

echo "placeholder" > /root/placeholder.txt
podman secret rm --all
/usr/local/bin/secret_list.sh | xargs -I% podman secret create "%" /root/placeholder.txt
podman secret ls
```

## Monitoring
- Install Node Exporter
```bash
adduser node_exporter --system
groupadd node_exporter
usermod -a -G node_exporter node_exporter
cd /root/homelab-rendered
src/debian/install_svcs.sh node_exporter
```
