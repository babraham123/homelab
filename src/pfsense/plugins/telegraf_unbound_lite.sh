#!/bin/sh
# /usr/local/bin/telegraf_unbound_lite.sh
# Copied from https://github.com/VictorRobellini/pfSense-Dashboard
HOSTNAME=$(hostname)

/usr/local/sbin/unbound-control -c /var/unbound/unbound.conf stats | grep -E 'total.num.cachemiss|total.num.cachehits'| xargs printf "unbound_lite,host=$HOSTNAME %s,%s\n"
