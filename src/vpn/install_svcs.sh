#!/usr/bin/env bash
# Installs VPN specific systemd services.
# Usage:
#   src/vpn/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

case $1 in
  headscale)
    HS_VERSION=$(curl -s "https://api.github.com/repos/juanfont/headscale/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=headscale.deb "https://github.com/juanfont/headscale/releases/download/v${HS_VERSION}/headscale_${HS_VERSION}_linux_amd64.deb"
    dpkg --install headscale.deb
    rm headscale.deb
    debian/add_homelab_tag.sh /usr/lib/systemd/system/headscale.service
    cp headscale/headscale.yaml /etc/headscale/config.yaml
    cp headscale/headscale_acl.hujson /etc/headscale/acl.hujson
    ;;
  tailscale)
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt update
    sudo apt install -y tailscale
    debian/add_homelab_tag.sh /usr/lib/systemd/system/tailscaled.service
    ;;
  haproxy)
    apt install -y haproxy
    debian/add_homelab_tag.sh /usr/lib/systemd/system/haproxy.service
    mkdir -p /etc/haproxy/certs
    cp haproxy/haproxy.cfg /etc/haproxy
    curl https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/haproxy/dhparam
    if [ ! -f /etc/haproxy/certs/vpnui.all.pem ]; then
      # placeholder cert
      openssl req -x509 -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem -sha256 -days 90 -subj '/CN=vpn-ui.{{ site.url }}'
      cat key.pem cert.pem > /etc/haproxy/certs/vpnui.all.pem
      rm ./*.pem
    fi
    ;;
  headscale-ui)
    apt install -y gcc python3-poetry
    mkdir -p /var/opt/headscale-ui/data
    pushd /var/opt/headscale-ui
    HSUI_VERSION=$(curl -s "https://api.github.com/repos/iFargle/headscale-webui/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget "https://github.com/iFargle/headscale-webui/archive/refs/tags/v${HSUI_VERSION}.tar.gz" -O - | tar xz
    mv "headscale-webui-${HSUI_VERSION}"/* .
    poetry install --only main
    popd
    cp headscale/headscale-ui.service /etc/systemd/system
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl enable "$1"
systemctl restart "$1"
systemctl status "$1"
