#!/bin/bash
case $1 in
  db)
    mkdir -p /var/opt/db
    ;;
  web)
    install_quadlet services/web/web.container
    ;;
esac
