#!/usr/bin/env bash
# Initializes the FluentBit config file to include custom services.
# Usage:
#   /etc/opt/fluentbit/prestart.sh

set -euo pipefail

rm -f /etc/opt/fluentbit/config.conf

line_num=$(sed -n '/PLACEHOLDER/=' /etc/opt/fluentbit/config_template.conf)
if ! [[ $line_num =~ ^[0-9]+$ ]]; then
  echo "error: could not locate end of input section" >&2
  exit 1
fi

head -n $((line_num - 1)) /etc/opt/fluentbit/config_template.conf > /etc/opt/fluentbit/config.conf

/usr/local/bin/list_services.sh | \
  xargs -I% echo "    Systemd_filter _SYSTEMD_UNIT=%.service" >> \
  /etc/opt/fluentbit/config.conf

tail -n +$((line_num + 1)) /etc/opt/fluentbit/config_template.conf >> /etc/opt/fluentbit/config.conf
