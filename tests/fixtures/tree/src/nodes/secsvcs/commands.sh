#!/bin/bash
case $1 in
  install_certs)
    cp /home/autoadmin/*.pem /etc/opt/certificates
    ;;
esac
