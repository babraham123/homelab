#!/usr/bin/env bash
# /etc/opt/fluentbit/prestart.sh

set -euo pipefail

cp /etc/opt/fluentbit/config_template.conf /etc/opt/fluentbit/config.conf

/usr/local/bin/list_services.sh | \
  xargs -I% sed -i "" "s/[INPUT].*/&\\n    Systemd_filter _SYSTEMD_UNIT=%.service/" \
  /etc/opt/fluentbit/config.conf
