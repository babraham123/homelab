#!/bin/bash
case $1 in
  node_exporter)
    install -D -m 644 -t /etc/systemd/system base/node_exporter/node_exporter.service
    ;;
  image_updater)
    install -D -m 644 -t /etc/systemd/system base/podman/image_updater.timer
    ;;
esac
