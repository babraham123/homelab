#!/bin/bash
case $1 in
  install_dispatcher)
    cp /root/homelab-rendered/src/base/debian/dispatcher.sh /usr/local/bin
    ;;
esac
