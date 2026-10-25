#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/base/debian/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

cd "$rendered"
watch_homelab_units

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
    install -D -m 644 -t /etc/systemd/system/mdns_repeater.service.d ../base/mdns_repeater/retry.conf
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
    # skopeo comes from podman's alvistack repo, which drops superseded versions
    apt update
    apt install -y skopeo wget gnupg
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
      gpg --dearmor --yes -o /usr/share/keyrings/trivy.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      > /etc/apt/sources.list.d/trivy.list
    apt update
    apt install -y trivy
    # github.com/babraham123/podman-image-updater, pinned to a commit and its file's hash
    commit=ec6da3687f2d1d1292099bfe21e13f1714b1b68f
    sha=d8556c5912a09f44bd3f1fa51feecef20c3201bccda8b374bc79e9b26390b9e2
    url="https://raw.githubusercontent.com/babraham123/podman-image-updater/${commit}/image_updater.py"
    wget --output-document=image_updater.py "$url"
    echo "${sha}  image_updater.py" | sha256sum --check || die "checksum mismatch: $url"
    install -D image_updater.py /usr/local/bin/image_updater
    rm image_updater.py
    # Its default config path; a link, so a deploy updates the image list in place
    install -d -m 700 /etc/image_updater
    ln -sfn "${rendered}/base/podman/image_updater.json" /etc/image_updater/config.json
    install -D -m 644 -t /etc/systemd/system base/podman/image_updater.service \
      base/podman/image_updater.timer
    mkdir -p /etc/systemd/system/image_updater.timer.d
    printf '[Timer]\nOnCalendar=*-*-* %s:00\n' "$slot" > /etc/systemd/system/image_updater.timer.d/slot.conf
    systemctl daemon-reload
    # Enabling the timer is the per-VM cutover from podman-auto-update.timer
    # (docs/maintenance.md), so installing leaves it as it was.
    exit 0
    ;;
  net_probe)
    # Ookla's CLI ships no checksums, so the tarball is pinned here; the iperf3 package
    # asks whether to run its own daemon, and the default is no.
    url=https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
    sha=5690596c54ff9bed63fa3732f818a05dbc2db19ad36ed68f21ca5f64d5cfeeb7
    wget --output-document=speedtest.tgz "$url"
    echo "${sha}  speedtest.tgz" | sha256sum --check || die "checksum mismatch: $url"
    tar xzf speedtest.tgz speedtest
    install -D -t /usr/local/bin speedtest
    rm speedtest speedtest.tgz
    DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
    # The probe itself, pinned to a commit; base/net_probe/config.json is its config
    url=https://raw.githubusercontent.com/babraham123/net-probe/53d791be849c30d0596349f793152a976dcf49b6/net_probe.py
    sha=e54c3b9e961018a81327e6cc51e1eb61f19f48a032dcc389b75e507d4ecae1b0
    wget --output-document=net_probe.py "$url"
    echo "${sha}  net_probe.py" | sha256sum --check || die "checksum mismatch: $url"
    install -D net_probe.py /usr/local/bin/net_probe
    rm net_probe.py
    install -D -m 644 -t /etc/systemd/system base/net_probe/net_probe.service base/net_probe/net_probe.timer
    systemctl daemon-reload
    systemctl enable net_probe.timer
    systemctl restart net_probe.timer
    exit 0
    ;;
  iperf3_server)
    DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
    install -D -m 644 -t /etc/systemd/system base/iperf3_server/iperf3_server.service
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
