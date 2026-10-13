#!/bin/bash
# Installs websvcs specific systemd services.
# Usage:
#   src/nodes/websvcs/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/svcs_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/svcs_lib.sh"

# Only the wyoming cases, not in use, call this
# function install_wyoming() {
#   rm -rf /etc/opt/wyoming/src
#   mkdir -p /etc/opt/wyoming/src
#   wget "https://github.com/rhasspy/wyoming-addons/archive/refs/heads/master.tar.gz" -O - | \
#     tar -xz -C /etc/opt/wyoming/src --strip-components=1
# }

# backup.sh snapshots the apps' SQLite databases.
install_sqlite3() {
  command -v sqlite3 > /dev/null || apt-get install -y sqlite3
}

# Usage: install_timer DIR NAME; NAME.service is a oneshot that NAME.timer starts
install_timer() {
  install -D -m 644 -t /etc/systemd/system "$1/$2.service" "$1/$2.timer"
  systemctl daemon-reload
  systemctl enable --now "$2.timer"
}

require_media() {
  # Unmounted, mkdir would put the library on the root disk.
  mountpoint -q /srv/media || die "/srv/media is not mounted"
}

cd "$rendered"

# Every image the case's quadlets name is downloaded (or built) and passes the scan gate
# before any quadlet is copied; a blocked image stops the install here.
base/podman/image_updater.sh install "${1:?usage: $0 SERVICE_NAME}"

case $1 in
  traefik)
    install_traefik_config websvcs
    install_quadlet nodes/websvcs/traefik/traefik.container
    reload_restart traefik
    ;;
  vmagent)
    install -D -m 644 -t /etc/opt/vmagent nodes/websvcs/prometheus.yml
    base/podman/render_host.sh websvcs services/victoriametrics/vmagent.container
    install_quadlet services/victoriametrics/vmagent.container services/victoriametrics/vmagentdata.volume
    reload_restart vmagent
    ;;
  nginx)
    install -D -m 644 -t /etc/opt/nginx/conf services/nginx/nginx.conf services/nginx/mime.types
    install_quadlet services/nginx/nginx.container
    # Placeholder release; homesite's deploy swaps the www symlink to newer ones.
    if [ ! -e /var/opt/nginx/www ]; then
      install -D -m 644 -t /var/opt/nginx/releases/00000000T000000Z/www services/nginx/index.html
      install -D -m 644 -t /var/opt/nginx/releases/00000000T000000Z/error services/nginx/404.html
      ln -s releases/00000000T000000Z /var/opt/nginx/www
    fi
    reload_restart nginx
    ;;
  homepage)
    rm -rf /etc/opt/homepage/config/*
    install -D -m 744 -t /etc/opt/homepage/config services/homepage/*.yaml
    chown -R 1000:1000 /etc/opt/homepage/config
    chmod 744 /etc/opt/homepage/config
    install -D -m 644 -t /etc/opt/homepage/images services/homepage/images/*
    install_quadlet services/homepage/homepage.container
    reload_restart homepage
    ;;
  isso)
    install -D -m 644 -t /etc/opt/isso/config services/isso/homesite.cfg
    install_quadlet services/isso/isso.container services/isso/issodb.volume
    reload_restart isso
    ;;
  guacamole)
    mkdir -p /etc/opt/guacamole/certs
    mkdir -p /etc/opt/guacamole/config
    chown -R 1001:1001 /etc/opt/guacamole
    install_quadlet services/guacamole/guacamole.container
    reload_restart guacamole
    ;;
  guacd)
    mkdir -p /etc/opt/guacd
    install_quadlet services/guacamole/guacd.container
    reload_restart guacd
    ;;
  linkding)
    install_sqlite3
    require_media
    mkdir -p /var/opt/linkding /srv/media/archive/linkding
    install_quadlet services/linkding/linkding.container
    reload_restart linkding
    ;;
  readeck)
    install_sqlite3
    require_media
    mkdir -p /var/opt/readeck /srv/media/archive/readeck
    install_quadlet services/readeck/readeck.container
    reload_restart readeck
    ;;
  linkding_handoff)
    install_timer services/readeck linkding_handoff
    ;;
  # Not in use: uncomment and add to src/nodes/websvcs/inventory.yml to install again
#   finance_exporter)
#     rm -rf /etc/opt/finance_exporter/src
#     mkdir -p /etc/opt/finance_exporter/src
#     install -D -m 644 -t /etc/opt/finance_exporter services/finance_exporter/config.yaml
#     wget "https://github.com/babraham123/finance-exporter/archive/refs/heads/main.tar.gz" -O - | \
#       tar -xz -C /etc/opt/finance_exporter/src --strip-components=1
#     podman build -t finance_exporter /etc/opt/finance_exporter/src
#     install_quadlet services/finance_exporter/finance_exporter.container
#     reload_restart finance_exporter
#     ;;
#   go2rtc)
#     install -D -m 644 -t /etc/opt/go2rtc services/go2rtc/config.yaml
#     install_quadlet services/go2rtc/go2rtc.container
#     reload_restart go2rtc
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
#     install_quadlet services/wyoming/piper.container
#     reload_restart piper
#     ;;
#   whisper)
#     mkdir -p /etc/opt/whisper
#     mkdir -p /var/opt/whisper
#     install_wyoming
#     WW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-faster-whisper/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#
#     podman build -t whisper /etc/opt/wyoming/src/whisper \
#       --build-arg WYOMING_WHISPER_VERSION="$WW_VERSION"
#     install_quadlet services/wyoming/whisper.container
#     reload_restart whisper
#     ;;
#   openwakeword)
#     mkdir -p /etc/opt/openwakeword
#     mkdir -p /var/opt/openwakeword
#     install_wyoming
#     OW_VERSION=$(curl -s "https://api.github.com/repos/rhasspy/wyoming-openwakeword/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
#
#     podman build -t openwakeword /etc/opt/wyoming/src/openwakeword \
#       --build-arg WYOMING_OPENWAKEWORD_VERSION="$OW_VERSION"
#     install_quadlet services/wyoming/openwakeword.container
#     reload_restart openwakeword
#     ;;
  fluentbit)
    install_fluentbit_config
    base/podman/render_host.sh websvcs services/fluentbit/fluentbit.container
    install_quadlet services/fluentbit/fluentbit.container services/fluentbit/fbdata.volume
    reload_restart fluentbit
    ;;
  snapraid)
    # Media array: snapraid parity over the passed-through HDDs, mergerfs union, SMART
    # on the guest side since the SATA controller is passed through whole. Disk layout
    # (partitions, mkfs, fstab, first sync) is manual: docs/guides/pve2_storage.md.
    apt-get install -y snapraid mergerfs smartmontools
    mkdir -p /var/snapraid
    install -D -m 644 services/snapraid/snapraid.conf /etc/snapraid.conf
    install_bin services/snapraid/snapraid_run.sh
    install -D -m 644 -t /etc/systemd/system services/snapraid/snapraid-*.service services/snapraid/snapraid-*.timer
    systemctl daemon-reload
    systemctl enable --now smartmontools
    if grep -q '^/dev/disk' services/snapraid/media.fstab; then
      systemctl enable --now snapraid-sync.timer snapraid-scrub.timer
    else
      # No disks declared in vars.yml yet: the timers would only fail
      systemctl disable --now snapraid-sync.timer snapraid-scrub.timer 2> /dev/null || true
    fi
    ;;
  storyteller)
    install_sqlite3
    require_media
    mkdir -p /var/opt/storyteller /srv/media/books/readalouds/{books,articles} \
      /srv/media/books/storyteller/{assets,uploads}
    # Storyteller runs as 1000:1000 and writes metadata edits into the books.
    chown 1000:1000 /srv/media/books/readalouds /srv/media/books/readalouds/{books,articles} \
      /srv/media/books/storyteller/{assets,uploads}
    install -D -m 644 -t /etc/opt/storyteller services/storyteller/config.json
    install_quadlet services/storyteller/storyteller.container
    reload_restart storyteller
    ;;
  calliope)
    require_media
    mkdir -p /etc/opt/calliope/voices /srv/media/books/narrate/{inbox,work,failed} \
      /srv/media/books/readalouds/{books,articles}
    install -D -m 644 -t /etc/opt/calliope services/calliope/calliope_batch.py
    install_quadlet services/calliope/calliope.container services/calliope/calliope_cache.volume
    install -D -m 644 -t /etc/systemd/system services/calliope/calliope.path \
      services/calliope/calliope.timer
    # calliope.service is a oneshot; the path unit and the timer start it.
    systemctl daemon-reload
    systemctl enable --now calliope.path calliope.timer
    ;;
  readeck_narrate)
    install_timer services/readeck readeck_narrate
    ;;
  *)
    die "unknown service: $1"
    ;;
esac
