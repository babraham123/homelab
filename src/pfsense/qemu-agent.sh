#!/bin/sh
# Initiates the QEMU Guest Agent on pfsense startup.
# Usage:
#   /usr/local/etc/rc.d/qemu-agent.sh

sleep 3
service qemu-guest-agent start
