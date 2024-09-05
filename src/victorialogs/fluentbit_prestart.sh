#!/usr/bin/env bash
# Initializes the FluentBit config file to include custom services.
# Usage:
#   /etc/opt/fluentbit/prestart.sh

set -euo pipefail

rm -f /etc/opt/fluentbit/config.conf
head -n16 /etc/opt/fluentbit/config_template.conf > /etc/opt/fluentbit/config.conf

/usr/local/bin/list_services.sh | \
  xargs -I% echo "    Systemd_filter _SYSTEMD_UNIT=%.service" >> \
  /etc/opt/fluentbit/config.conf

tail -n+17 /etc/opt/fluentbit/config_template.conf >> /etc/opt/fluentbit/config.conf
