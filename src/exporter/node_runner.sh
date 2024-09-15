#!/usr/bin/env bash
# Wrapper script to run node_exporter with custom services.
# Usage:
#   /usr/local/bin/node_exporter_runner.sh
set -euo pipefail

# TODO: Convert to a j2 template

# Filter for custom services
SVC_LIST=$(/usr/local/bin/list_services.sh | tr '\n' '|' | head -c -1)

# Ref: https://github.com/prometheus/node_exporter?tab=readme-ov-file#collectors
/usr/local/bin/node_exporter \
  --collector.textfile.directory /var/lib/node_exporter/textfile_collector \
  --collector.systemd \
  --collector.systemd.unit-include="($SVC_LIST)\\.service"
