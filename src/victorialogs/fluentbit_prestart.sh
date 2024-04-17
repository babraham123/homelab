#!/usr/bin/env bash
# /etc/opt/fluentbit/prestart.sh

set -euo pipefail

rm -f /etc/opt/fluentbit/config.conf
head -n14 /etc/opt/fluentbit/config_template.conf > /etc/opt/fluentbit/config.conf

/usr/local/bin/list_services.sh | \
  xargs -I% echo "    Systemd_filter _SYSTEMD_UNIT=%.service" >> \
  /etc/opt/fluentbit/config.conf

tail -n+15 /etc/opt/fluentbit/config_template.conf >> /etc/opt/fluentbit/config.conf
