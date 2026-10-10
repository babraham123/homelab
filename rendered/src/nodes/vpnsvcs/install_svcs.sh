#!/bin/bash
# Installs VPN specific systemd services.
# Usage:
#   src/nodes/vpnsvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

# HAProxy and Headscale serve metrics on the podman bridge gateway (net.network)
nonlocal_bind() {
  install -D -m 644 nodes/vpnsvcs/nonlocal_bind.conf /etc/sysctl.d/90-homelab-nonlocal-bind.conf
  sysctl -p /etc/sysctl.d/90-homelab-nonlocal-bind.conf
}

case $1 in
  headscale)
    # sqlite3 takes the consistent DB snapshot for backup.sh
    apt install -y sqlite3
    nonlocal_bind
    HS_VERSION=$(curl -s "https://api.github.com/repos/juanfont/headscale/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=headscale.deb "https://github.com/juanfont/headscale/releases/download/v${HS_VERSION}/headscale_${HS_VERSION}_linux_amd64.deb"
    dpkg --install headscale.deb
    rm headscale.deb
    base/debian/add_homelab_tag.sh /usr/lib/systemd/system/headscale.service
    install -D -m 644 services/headscale/headscale.yaml /etc/headscale/config.yaml
    install -D -m 644 services/headscale/headscale_acl.hujson /etc/headscale/acl.hujson
    touch /etc/opt/secrets/hs_oidc_id
    oidc_id=$(cat /etc/opt/secrets/hs_oidc_id | tr -d '\n')
    sed -i "s/PLACEHOLDER_ID/$oidc_id/g" /etc/headscale/config.yaml
    ;;
  tailscaled)
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt update
    sudo apt install -y tailscale
    base/debian/add_homelab_tag.sh /usr/lib/systemd/system/tailscaled.service
    ;;
  haproxy)
    apt install -y haproxy
    nonlocal_bind
    base/debian/add_homelab_tag.sh /usr/lib/systemd/system/haproxy.service
    install -D -m 644 -t /etc/haproxy services/haproxy/haproxy.cfg
    curl https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/haproxy/dhparam
    mkdir -p /etc/haproxy/countries

    touch /etc/haproxy/countries/RU.map
    chmod 644 /etc/haproxy/countries/RU.map
    touch /etc/haproxy/countries/CN.map
    chmod 644 /etc/haproxy/countries/CN.map
    ;;
  geoip_generator)
    podman build -t geoip_generator -f services/haproxy/geoip_generator.Containerfile services/haproxy
    podman image prune -f
    install -D -m 644 -t /etc/containers/systemd services/haproxy/geoip_generator.container
    install -D -m 644 -t /etc/systemd/system services/haproxy/geoip_generator.timer
    systemctl daemon-reload
    systemctl enable geoip_generator.timer
    systemctl restart geoip_generator.timer
    exit 0
    ;;
  fluentbit)
    install -D -m 644 services/fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit services/fluentbit/journald.lua
    install -D -m 644 base/debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    /root/homelab-rendered/src/base/podman/render_host.sh vpnsvcs services/fluentbit/fluentbit.container
    install -D -m 644 -t /etc/containers/systemd services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent nodes/vpnsvcs/prometheus.yml
    /root/homelab-rendered/src/base/podman/render_host.sh vpnsvcs services/victoriametrics/vmagent.container
    install -D -m 644 -t /etc/containers/systemd services/victoriametrics/vmagent.container services/victoriametrics/vmagentdata.volume
    ;;
  deadman)
    install -d -m 700 /var/lib/deadman
    install -D -m 644 -t /etc/systemd/system nodes/vpnsvcs/deadman.{service,timer}

    systemctl daemon-reload
    systemctl enable deadman.timer
    systemctl restart deadman.timer
    exit 0
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl enable "$1"
systemctl restart "$1"
systemctl status "$1" --no-pager
