#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/base/debian/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

cd "$rendered"

case $1 in
  mdns_repeater)
    apt install -y build-essential
    git clone https://github.com/babraham123/mdns-repeater
    cd mdns-repeater
    make all
    install -D -t /usr/local/bin mdns-repeater
    from=$(ip -j -4 route show to default | jq -r '.[0].dev')
    to=$(podman network inspect systemd-net | jq -r '.[0].network_interface')
    echo "Enabling mdns over the following interfaces: $from -> $to"
    echo "# Options to pass to mdns-repeater" > /etc/default/mdns-repeater
    echo "MDNS_REPEATER_OPTS=\"$from $to\"" >> /etc/default/mdns-repeater
    ../base/debian/add_homelab_tag.sh mdns-repeater.service
    install -D -m 644 mdns-repeater.service /etc/systemd/system/mdns_repeater.service
    cd ..
    rm -rf mdns*
    ;;
  node_exporter)
    NE_VERSION=$(curl -s "https://api.github.com/repos/prometheus/node_exporter/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    wget --output-document=ne.tar.gz "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/node_exporter-${NE_VERSION}.linux-amd64.tar.gz"
    tar xzf ne.tar.gz
    install -D -o node_exporter -g node_exporter -t /usr/local/bin \
      "node_exporter-${NE_VERSION}.linux-amd64/node_exporter"
    rm -rf "node_exporter-${NE_VERSION}.linux-amd64" ne.tar.gz

    install -d -o node_exporter -g node_exporter /var/lib/node_exporter \
      /var/lib/node_exporter/textfile_collector

    install_lib
    install -D -o node_exporter -g node_exporter base/node_exporter/node_runner.sh \
      /usr/local/bin/node_exporter_runner.sh
    install -D -m 644 -t /etc/systemd/system base/node_exporter/node_exporter.service
    ;;
  nvidia_gpu_exporter)
    # The deb adds the nvidia_gpu_exporter user and unit; it serves :9835/metrics.
    NGE_VERSION=$(curl -s "https://api.github.com/repos/utkuozdemir/nvidia_gpu_exporter/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
    deb="nvidia-gpu-exporter_${NGE_VERSION}_linux_amd64.deb"
    url="https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${NGE_VERSION}"
    wget "$url/$deb" "$url/checksums.txt"
    sha256sum --check --ignore-missing checksums.txt || die "checksum mismatch: $deb"
    apt install -y "./$deb"
    rm "$deb" checksums.txt
    ;;
  image_updater)
    # 30 minutes apart; the notification path on secsvcs goes last
    case $(hostname) in
      vpnsvcs) slot=20:00 ;;
      homesvcs) slot=20:30 ;;
      websvcs) slot=21:00 ;;
      secsvcs) slot=21:30 ;;
      *) die "no image_updater slot for $(hostname)" ;;
    esac
    # python3 runs image_updater.py
    apt install -y python3 skopeo wget gnupg
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
      gpg --dearmor --yes -o /usr/share/keyrings/trivy.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      > /etc/apt/sources.list.d/trivy.list
    apt update
    apt install -y trivy
    install -D -m 644 -t /etc/systemd/system base/podman/image_updater.service \
      base/podman/image_updater.timer
    mkdir -p /etc/systemd/system/image_updater.timer.d
    printf '[Timer]\nOnCalendar=*-*-* %s:00\n' "$slot" > /etc/systemd/system/image_updater.timer.d/slot.conf
    systemctl daemon-reload
    # Enabling the timer is the per-VM cutover from podman-auto-update.timer
    # (docs/maintenance.md), so installing leaves it as it was.
    exit 0
    ;;
  vm_watchdog)
    install_bin base/vm_watchdog/vm_watchdog.sh
    install -D -m 644 -t /etc/systemd/system base/vm_watchdog/vm_watchdog.service
    ;;
  *)
    die "unknown service: $1"
    ;;
esac

systemctl enable "$1"
reload_restart "$1"
