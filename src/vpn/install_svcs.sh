#!/usr/bin/env bash
# src/debian/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

case $1 in
  headscale)
    HS_VERSION=$(curl -s "https://api.github.com/repos/juanfont/headscale/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=headscale.deb "https://github.com/juanfont/headscale/releases/download/v${HS_VERSION}/headscale_${HS_VERSION}_linux_amd64.deb"
    dpkg --install headscale.deb
    rm headscale.deb
    src/debian/add_homelab_tag.sh /etc/systemd/system/headscale.service
    cp headscale/headscale.yaml /etc/headscale/config.yaml
    cp src/headscale/headscale_acl.hujson /etc/headscale/acl.hujson
    ;;
  tailscale)
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt update
    sudo apt install -y tailscale
    src/debian/add_homelab_tag.sh /etc/systemd/system/tailscaled.service
    ;;
  haproxy)
    apt install -y haproxy
    src/debian/add_homelab_tag.sh /etc/systemd/system/haproxy.service
    mkdir -p /etc/haproxy/certs
    cp src/haproxy/haproxy.cfg /etc/haproxy
    curl https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/haproxy/dhparam
    if [ ! -f /etc/haproxy/certs/vpnui.all.pem ]; then
      # placeholder cert
      openssl req -x509 -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem -sha256 -days 90 -subj '/CN=vpn-ui.{{ site.url }}'
      cat key.pem cert.pem > /etc/haproxy/certs/vpnui.all.pem
      rm ./*.pem
    fi
    ;;
  *)
    echo "Unknown service: $1"
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl enable "$1"
systemctl restart "$1"
systemctl status "$1"
