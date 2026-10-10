#!/bin/bash
# Installs a variety of general purpose systemd services.
# Usage:
#   src/base/debian/install_svcs.sh SERVICE_NAME

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

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
  vm_watchdog)
    install_bin nodes/pve1/vm_watchdog.sh
    install -D -m 644 -t /etc/systemd/system nodes/pve1/vm_watchdog.service
    ;;
  *)
    die "unknown service: $1"
    ;;
esac

systemctl enable "$1"
reload_restart "$1"
