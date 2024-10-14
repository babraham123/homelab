# Podman setup
Initial setup to install Proxmox and configure it with the relevant scripts and services.

- Setup [Debian Linux](./debian.md)
- Make sure to do VM Host setup for [PVE1](./pve1.md) and [PVE2](./pve2.md).
- Review container security measures, for example [ref](https://www.panoptica.app/research/7-ways-to-escape-a-container)

## Install Podman
- Install dependencies
```bash
sudo su
apt install -y age jq python3-pip
pip3 install --break-system-packages jinjanator jinjanator-plugin-ansible passlib

YQ_VERSION=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
wget "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" -O - | tar xz
mv yq_linux_amd64 /usr/bin/yq
./install-man-page.sh
rm yq* install-man-page.sh
```
- Install podman: [ref](https://podman.io/docs/installation#linux-distributions)
```bash
# POD_VERSION=$(curl -s "https://api.github.com/repos/containers/podman/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
# wget "https://github.com/containers/podman/releases/download/v${POD_VERSION}/podman-remote-static-linux_amd64.tar.gz"
# tar -vxf podman-remote-static-linux_amd64.tar.gz

curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/Debian_Testing/Release.key \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg > /dev/null
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg]\
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/Debian_Testing/ /" \
  | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list > /dev/null

apt update
apt -y upgrade
apt -y install podman libgpgme11-dev buildah libyajl2
```

## Networking
- Account for conflicts between the podman network and the firewall, [bug](https://stackoverflow.com/questions/70870689/configure-ufw-for-podman-on-port-443)
```bash
ufw allow http
ufw allow https

cd /root/homelab-rendered
cp src/$HOST/net.network /etc/containers/systemd
systemctl daemon-reload
NET_IFACE=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
# use {{ websvcs.interface }} on websvcs
ufw route allow in on {{ secsvcs.interface }} out on $NET_IFACE to any port 80,443 proto tcp
```

- Allow access from container to host
```bash
# scrape node_exporter
# use {{ websvcs.container_subnet }}.3, {{ websvcs.interface }} on websvcs
ufw allow in from {{ secsvcs.container_subnet }}.3 to any port 9100 proto tcp
ufw route allow in on $NET_IFACE out on {{ secsvcs.interface }} to any port 9100 proto tcp
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
cp src/podman/*.sh /usr/local/bin
cp src/podman/containers.conf /etc/containers

echo "placeholder" > /root/placeholder.txt
podman secret rm --all
/usr/local/bin/list_secrets.sh | xargs -I% podman secret create "%" /root/placeholder.txt
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
