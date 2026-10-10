#!/bin/sh
case $1 in
  install_certs)
    cp /home/autoadmin/router.*.pem /etc/certs
    ;;
esac
