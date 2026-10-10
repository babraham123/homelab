#!/bin/bash
# Installs websvcs specific systemd services.
# Usage:
#   src/websvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

# Only the wyoming cases, not in use, call this
# function install_wyoming() {
#   rm -rf /etc/opt/wyoming/src
#   mkdir -p /etc/opt/wyoming/src
#   wget "https://github.com/rhasspy/wyoming-addons/archive/refs/heads/main.tar.gz" -O - | \
#     tar -xz -C /etc/opt/wyoming/src --strip-components=1
# }

cd /root/homelab-rendered/src

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    install -D -m 644 -t /etc/opt/traefik/config/dynamic websvcs/traefik/*.yml traefik/dynamic/*.yml
    install -D -m 644 traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    install -D -m 644 -t /etc/containers/systemd websvcs/traefik/traefik.container
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent websvcs/prometheus.yml
    /root/homelab-rendered/src/podman/render_host.sh websvcs victoriametrics/vmagent.container
    install -D -m 644 -t /etc/containers/systemd victoriametrics/vmagent.container victoriametrics/vmagentdata.volume
    ;;
  nginx)
    install -D -m 644 -t /etc/opt/nginx/conf nginx/nginx.conf nginx/mime.types
    install -D -m 644 -t /etc/containers/systemd nginx/nginx.container
    # Placeholder release; homesite's deploy swaps the www symlink to newer ones.
    if [ ! -e /var/opt/nginx/www ]; then
      install -D -m 644 -t /var/opt/nginx/releases/00000000T000000Z/www nginx/index.html
      install -D -m 644 -t /var/opt/nginx/releases/00000000T000000Z/error nginx/404.html
      ln -s releases/00000000T000000Z /var/opt/nginx/www
    fi
    ;;
  homepage)
    rm -rf /etc/opt/homepage/config/*
    install -D -m 744 -t /etc/opt/homepage/config homepage/*.yaml
    chown -R 1000:1000 /etc/opt/homepage/config
    chmod 744 /etc/opt/homepage/config
    install -D -m 644 -t /etc/opt/homepage/images homepage/images/*
    install -D -m 644 -t /etc/containers/systemd homepage/homepage.container
    ;;
  isso)
    install -D -m 644 -t /etc/opt/isso/config isso/homesite.cfg
    install -D -m 644 -t /etc/containers/systemd isso/isso.container isso/issodb.volume
    ;;
  guacamole)
    mkdir -p /etc/opt/guacamole/certs
    mkdir -p /etc/opt/guacamole/config
    chown -R 1001:1001 /etc/opt/guacamole
    install -D -m 644 -t /etc/containers/systemd guacamole/guacamole.container
    ;;
  guacd)
    mkdir -p /etc/opt/guacd
    install -D -m 644 -t /etc/containers/systemd guacamole/guacd.container
    ;;
  # Not in use: uncomment and add to src/nodes.yml to install again
#   archivebox)
#     mkdir -p /var/opt/archivebox
#     chown -R 911:911 /var/opt/archivebox
#     install -D -m 644 -t /etc/containers/systemd archivebox/archivebox.container archivebox/chromium.volume
#
#     rm -rf /etc/opt/novnc/src
#     mkdir -p /etc/opt/novnc/src
#     wget "https://github.com/babraham123/docker-novnc/archive/refs/heads/master.tar.gz" -O - | \
#       tar -xz -C /etc/opt/novnc/src --strip-components=1
#     podman build -t novnc /etc/opt/novnc/src
#     install -D -m 644 -t /etc/containers/systemd archivebox/novnc.container
#     ;;
#   finance_exporter)
#     rm -rf /etc/opt/finance_exporter/src
#     mkdir -p /etc/opt/finance_exporter/src
#     install -D -m 644 -t /etc/opt/finance_exporter finance_exporter/config.yaml
#     wget "https://github.com/babraham123/finance-exporter/archive/refs/heads/main.tar.gz" -O - | \
#       tar -xz -C /etc/opt/finance_exporter/src --strip-components=1
#     podman build -t finance_exporter /etc/opt/finance_exporter/src
#     install -D -m 644 -t /etc/containers/systemd finance_exporter/finance_exporter.container
#     ;;
#   go2rtc)
#     install -D -m 644 -t /etc/opt/go2rtc go2rtc/config.yaml
#     install -D -m 644 -t /etc/containers/systemd go2rtc/go2rtc.container
#     ;;
#   piper)
#     mkdir -p /etc/opt/piper
#     mkdir -p /var/opt/piper
#     install_wyoming
#     WP_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-piper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#     WY_VERSION=$(curl -s "https://api.github.com/repos/OHF-voice/wyoming/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#     # TODO: Watch for migration to https://github.com/OHF-Voice/piper1-gpl
#     PI_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/piper/releases" | grep -Po '"tag_name": "v\K[0-9.]+' | head -1)
#
#     podman build -t piper /etc/opt/wyoming/src/piper \
#       --build-arg WYOMING_PIPER_VERSION="$WP_VERSION" \
#       --build-arg WYOMING_VERSION="$WY_VERSION" \
#       --build-arg BINARY_PIPER_VERSION="$PI_VERSION" \
#       --build-arg TARGETARCH="amd64" --build-arg TARGETVARIANT=""
#     install -D -m 644 -t /etc/containers/systemd wyoming/piper.container
#     ;;
#   whisper)
#     mkdir -p /etc/opt/whisper
#     mkdir -p /var/opt/whisper
#     install_wyoming
#     WW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-faster-whisper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#
#     podman build -t whisper /etc/opt/wyoming/src/whisper \
#       --build-arg WYOMING_WHISPER_VERSION="$WW_VERSION"
#     install -D -m 644 -t /etc/containers/systemd wyoming/whisper.container
#     ;;
#   openwakeword)
#     mkdir -p /etc/opt/openwakeword
#     mkdir -p /var/opt/openwakeword
#     install_wyoming
#     OW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-openwakeword/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#
#     podman build -t openwakeword /etc/opt/wyoming/src/openwakeword \
#       --build-arg WYOMING_OPENWAKEWORD_VERSION="$OW_VERSION"
#     install -D -m 644 -t /etc/containers/systemd wyoming/openwakeword.container
#     ;;
  fluentbit)
    install -D -m 644 fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    install -D -m 644 -t /etc/opt/fluentbit fluentbit/journald.lua
    install -D -m 644 debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
    systemctl restart systemd-journald
    /root/homelab-rendered/src/podman/render_host.sh websvcs fluentbit/fluentbit.container
    install -D -m 644 -t /etc/containers/systemd fluentbit/fluentbit.container fluentbit/fbdata.volume
    ;;
  snapraid)
    # Media array: snapraid parity over the passed-through HDDs, mergerfs union, SMART
    # on the guest side since the SATA controller is passed through whole. Disk layout
    # (partitions, mkfs, fstab, first sync) is manual: docs/guides/pve2_storage.md.
    apt-get install -y snapraid mergerfs smartmontools
    mkdir -p /var/snapraid
    install -D -m 644 snapraid/snapraid.conf /etc/snapraid.conf
    install -D -t /usr/local/bin snapraid/snapraid_run.sh
    install -D -m 644 -t /etc/systemd/system snapraid/snapraid-*.service snapraid/snapraid-*.timer
    systemctl daemon-reload
    systemctl enable --now smartmontools
    if grep -q '^/dev/disk' snapraid/media.fstab; then
      systemctl enable --now snapraid-sync.timer snapraid-scrub.timer
    else
      # No disks declared in vars.yml yet: the timers would only fail
      systemctl disable --now snapraid-sync.timer snapraid-scrub.timer 2> /dev/null || true
    fi
    exit 0
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl restart "$1"
systemctl status "$1" --no-pager
