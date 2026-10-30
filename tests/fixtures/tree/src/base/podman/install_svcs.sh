#!/bin/bash
case $1 in
  proxy)
    install_quadlet services/proxy/proxy.container
    install_dropins proxy
    ;;
esac
