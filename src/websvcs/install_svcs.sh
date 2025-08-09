#!/usr/bin/env bash
# Installs websvcs specific systemd services.
# Usage:
#   src/websvcs/install_svcs.sh SERVICE_NAME

set -euo pipefail

function install_wyoming() {
  rm -rf /etc/opt/wyoming/src
  wget "https://github.com/rhasspy/wyoming-addons/archive/refs/heads/main.tar.gz" -O - | \
    tar -xz -C /etc/opt/wyoming/src --strip-components=1
}

cd /root/homelab-rendered/src
mkdir -p /etc/containers/systemd
cp podman/*.sh /usr/local/bin

case $1 in
  traefik)
    mkdir -p /etc/opt/traefik/config/dynamic
    mkdir -p /etc/opt/traefik/config/static
    mkdir -p /etc/opt/traefik/certificates
    rm -rf /etc/opt/traefik/config/dynamic/*
    cp websvcs/traefik/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/dynamic/*.yml /etc/opt/traefik/config/dynamic
    cp traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
    cp websvcs/traefik/traefik.container /etc/containers/systemd
    ;;
  vmagent)
    mkdir -p /etc/opt/vmagent
    cp websvcs/prometheus.yml /etc/opt/vmagent
    /usr/local/bin/render_host.sh websvcs victoriametrics/vmagent.container
    mv victoriametrics/vmagent.container /etc/containers/systemd
    cp victoriametrics/vmagentdata.volume /etc/containers/systemd
    ;;
  nginx)
    mkdir -p /etc/opt/nginx/conf
    mkdir -p /var/opt/nginx/www/www
    mkdir -p /var/opt/nginx/www/error
    cp nginx/nginx.conf /etc/opt/nginx/conf
    cp nginx/mime.types /etc/opt/nginx/conf
    cp nginx/index.html /var/opt/nginx/www/www
    cp nginx/404.html /var/opt/nginx/www/error
    cp nginx/nginx.container /etc/containers/systemd
    ;;
  homepage)
    mkdir -p /etc/opt/homepage/config
    rm -rf /etc/opt/homepage/config/*
    cp homepage/*.yaml /etc/opt/homepage/config
    chown -R 1000:1000 /etc/opt/homepage/config
    chmod -R 744 /etc/opt/homepage/config
    cp -r homepage/images /etc/opt/homepage
    cp homepage/homepage.container /etc/containers/systemd
    ;;
  isso)
    mkdir -p /etc/opt/isso/config
    cp isso/homesite.cfg /etc/opt/isso/config
    cp isso/isso.container /etc/containers/systemd
    cp isso/issodb.volume /etc/containers/systemd
    ;;
  finance_exporter)
    rm -rf /etc/opt/finance_exporter/src
    mkdir -p /etc/opt/finance_exporter/src
    cp finance_exporter/config.yaml /etc/opt/finance_exporter
    cp finance_exporter/finance_exporter.container /etc/containers/systemd
    wget "https://github.com/babraham123/finance-exporter/archive/refs/heads/main.tar.gz" -O - | \
      tar -xz -C /etc/opt/finance_exporter/src --strip-components=1
    podman build -t finance_exporter /etc/opt/finance_exporter/src
    ;;
  go2rtc)
    mkdir -p /etc/opt/go2rtc
    cp go2rtc/config.yaml /etc/opt/go2rtc
    cp go2rtc/go2rtc.container /etc/containers/systemd
    ;;
  piper)
    mkdir -p /etc/opt/piper
    mkdir -p /var/opt/piper
    cp wyoming/piper.container /etc/containers/systemd
    install_wyoming
    WP_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-piper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    WY_VERSION=$(curl -s "https://api.github.com/repos/OHF-voice/wyoming/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    # TODO: Watch for migration to https://github.com/OHF-Voice/piper1-gpl
    PI_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/piper/releases" | grep -Po '"tag_name": "v\K[0-9.]+' | head -1)

    podman build -t piper /etc/opt/wyoming/src/piper \
      --build-arg WYOMING_PIPER_VERSION="$WP_VERSION" \
      --build-arg WYOMING_VERSION="$WY_VERSION" \
      --build-arg BINARY_PIPER_VERSION="$PI_VERSION" \
      --build-arg TARGETARCH="amd64" --build-arg TARGETVARIANT=""
    ;;
  whisper)
    mkdir -p /etc/opt/whisper
    mkdir -p /var/opt/whisper
    cp wyoming/whisper.container /etc/containers/systemd
    install_wyoming
    WW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-faster-whisper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    
    podman build -t whisper /etc/opt/wyoming/src/whisper \
      --build-arg WYOMING_WHISPER_VERSION="$WW_VERSION"
    ;;
  openwakeword)
    mkdir -p /etc/opt/openwakeword
    mkdir -p /var/opt/openwakeword
    cp wyoming/openwakeword.container /etc/containers/systemd
    install_wyoming
    OW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-openwakeword/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    
    podman build -t openwakeword /etc/opt/wyoming/src/openwakeword \
      --build-arg WYOMING_OPENWAKEWORD_VERSION="$OW_VERSION"
    ;;
  fluentbit)
    mkdir -p /etc/opt/fluentbit
    cp fluentbit/fluentbit.yaml.j2 /etc/opt/fluentbit/config.yaml.j2
    cp fluentbit/journald.lua /etc/opt/fluentbit
    /usr/local/bin/render_host.sh websvcs fluentbit/fluentbit.container
    mv fluentbit/fluentbit.container /etc/containers/systemd
    cp fluentbit/fbdata.volume /etc/containers/systemd
    ;;
  *)
    echo "error: unknown service: $1" >&2
    exit 1
    ;;
esac

systemctl daemon-reload
systemctl restart "$1"
systemctl status "$1"
