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
    # Pinned to a commit; git checks the tree against it
    mkdir mdns-repeater
    cd mdns-repeater
    git init --quiet
    git fetch --quiet --depth 1 https://github.com/babraham123/mdns-repeater \
      7ab67cbd1c9beea14d64c5ef3175caba62b687f5
    git checkout --quiet FETCH_HEAD
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
    ne="node_exporter-${NE_VERSION}.linux-amd64"
    url="https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}"
    wget "$url/$ne.tar.gz" "$url/sha256sums.txt"
    sha256sum --check --ignore-missing sha256sums.txt || die "checksum mismatch: $ne.tar.gz"
    tar xzf "$ne.tar.gz"
    # Root owns what the service runs and the textfiles it reads, so a compromised
    # exporter can't replace its own code or forge another job's metrics.
    install -D -t /usr/local/bin "$ne/node_exporter"
    rm -rf "$ne" "$ne.tar.gz" sha256sums.txt

    install -d -m 755 -o root -g root /var/lib/node_exporter \
      /var/lib/node_exporter/textfile_collector

    install_lib
    install -D base/node_exporter/node_runner.sh /usr/local/bin/node_exporter_runner.sh
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
    # github.com/babraham123/podman-image-updater, pinned to a release and its asset's hash
    tag=v1.0.0
    sha=156a3e03037889064ce831876a10f7d2de663a4ea75a1d34cc1603aba78cfb7b
    fetch_pinned "https://github.com/babraham123/podman-image-updater/releases/download/${tag}/image_updater" \
      "$sha" image_updater
    install -D image_updater /usr/local/bin/image_updater
    rm image_updater
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
    fetch_pinned https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz \
      5690596c54ff9bed63fa3732f818a05dbc2db19ad36ed68f21ca5f64d5cfeeb7 speedtest.tgz
    tar xzf speedtest.tgz speedtest
    install -D -t /usr/local/bin speedtest
    rm speedtest speedtest.tgz
    DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
    # github.com/babraham123/net-probe, pinned to a release and its asset's hash;
    # base/net_probe/config.json is its config
    tag=v1.0.0
    sha=453335caab35112ee881d2fedc30571a454d1f175885ac48d647ed84364551b3
    fetch_pinned "https://github.com/babraham123/net-probe/releases/download/${tag}/net_probe" \
      "$sha" net_probe
    install -D net_probe /usr/local/bin/net_probe
    rm net_probe
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
