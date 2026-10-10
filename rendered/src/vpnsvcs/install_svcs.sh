#!/bin/bash
# Installs VPN specific systemd services.
# Usage:
#   src/vpnsvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

cd /root/homelab-rendered/src

# HAProxy and Headscale serve metrics on the podman bridge gateway (net.network)
nonlocal_bind() {
  cp vpnsvcs/nonlocal_bind.conf /etc/sysctl.d/90-homelab-nonlocal-bind.conf
  sysctl -p /etc/sysctl.d/90-homelab-nonlocal-bind.conf
}

case $1 in
  headscale)
    # sqlite3 takes the consistent DB snapshot for backup_full.sh
    apt install -y sqlite3
    nonlocal_bind
    HS_VERSION=$(curl -s "https://api.github.com/repos/juanfont/headscale/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=headscale.deb "https://github.com/juanfont/headscale/releases/download/v${HS_VERSION}/headscale_${HS_VERSION}_linux_amd64.deb"
    dpkg --install headscale.deb
    rm headscale.deb
    debian/add_homelab_tag.sh /usr/lib/systemd/system/headscale.service
    cp headscale/headscale.yaml /etc/headscale/config.yaml
    cp headscale/headscale_acl.hujson /etc/headscale/acl.hujson
    touch /etc/opt/secrets/hs_oidc_id
    oidc_id=$(cat /etc/opt/secrets/hs_oidc_id | tr -d '\n')
    sed -i "s/PLACEHOLDER_ID/$oidc_id/g" /etc/headscale/config.yaml
    ;;
  tailscaled)
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt update
    sudo apt install -y tailscale
    debian/add_homelab_tag.sh /usr/lib/systemd/system/tailscaled.service
    ;;
  haproxy)
    apt install -y haproxy
    nonlocal_bind
    debian/add_homelab_tag.sh /usr/lib/systemd/system/haproxy.service
    cp haproxy/haproxy.cfg /etc/haproxy
    curl https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/haproxy/dhparam
    mkdir -p /etc/haproxy/countries

    touch /etc/haproxy/countries/RU.map
    chmod 644 /etc/haproxy/countries/RU.map
    touch /etc/haproxy/countries/CN.map
    chmod 644 /etc/haproxy/countries/CN.map
    ;;
  geoip_generator)
    mapper_bin="/home/autoadmin/haproxy-mapper"
    if [ -f "$mapper_bin" ]; then
      chown root:root "$mapper_bin"
      chmod 500 "$mapper_bin"
      mv "$mapper_bin" /usr/local/bin/
    fi
    cp haproxy/geoip_generator.py /usr/local/bin
    chmod +x /usr/local/bin/geoip_generator.py
    cp haproxy/geoip_generator.service /etc/systemd/system
    cp haproxy/geoip_generator.timer /etc/systemd/system

    systemctl daemon-reload
    systemctl enable geoip_generator.service
    systemctl enable geoip_generator.timer
    systemctl restart geoip_generator.timer
    exit 0
    ;;
  fluentbit)
    mkdir -p /etc/opt/fluentbit
    cp fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    cp fluentbit/journald.lua /etc/opt/fluentbit
    install -D -m 644 debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    /root/homelab-rendered/src/podman/render_host.sh vpnsvcs fluentbit/fluentbit.container
    mv fluentbit/fluentbit.container /etc/containers/systemd
    cp fluentbit/fbdata.volume /etc/containers/systemd
    systemctl daemon-reload
    systemctl restart fluentbit
    systemctl status fluentbit --no-pager
    exit 0
    ;;
  vmagent)
    mkdir -p /etc/opt/vmagent
    cp vpnsvcs/prometheus.yml /etc/opt/vmagent
    /root/homelab-rendered/src/podman/render_host.sh vpnsvcs victoriametrics/vmagent.container
    mv victoriametrics/vmagent.container /etc/containers/systemd
    cp victoriametrics/vmagentdata.volume /etc/containers/systemd
    systemctl daemon-reload
    systemctl restart vmagent
    systemctl status vmagent --no-pager
    exit 0
    ;;
  deadman)
    # The checker's credentials are hand-placed, like hs_oidc_*; fail here, not at 02:00.
    for f in alertmanager_admin_password msmtp_password deadman_ntfy_topic; do
      [[ -s /etc/opt/secrets/$f ]] || { echo "error: missing /etc/opt/secrets/$f" >&2; exit 1; }
    done
    # msmtp as on pve1, AppArmor profile on; the local override lets it run the password script
    echo "msmtp msmtp/apparmor boolean true" | debconf-set-selections
    apt install -y jq curl msmtp
    cp certificates/msmtprc /etc/msmtprc
    printf '%s\n' "/usr/bin/hostname PUx," "/root/homelab-rendered/src/vpnsvcs/msmtp_password.sh PUx," \
      > /etc/apparmor.d/local/usr.bin.msmtp
    apparmor_parser -r /etc/apparmor.d/usr.bin.msmtp
    install -d -m 700 /var/lib/deadman
    cp vpnsvcs/deadman.service /etc/systemd/system
    cp vpnsvcs/deadman.timer /etc/systemd/system

    systemctl daemon-reload
    systemctl enable deadman.timer
    systemctl restart deadman.timer
    systemctl start deadman.service
    systemctl status deadman.timer --no-pager
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
