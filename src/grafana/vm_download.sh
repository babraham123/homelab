#!/bin/sh
# Downloads the VictoriaMetrics and VictoriaLogs plugins for Grafana. Runs on startup.
# Usage:
#   /etc/opt/grafana/vm_download.sh
# https://github.com/VictoriaMetrics/victorialogs-datasource?tab=readme-ov-file

set -eu

VL_DS_PATH='/var/lib/grafana/plugins/victorialogs-datasource'
VM_DS_PATH='/var/lib/grafana/plugins/victoriametrics-datasource'
PLUGIN_PATH='/var/lib/grafana/plugins'

if [ -f ${VM_DS_PATH}/plugin.json ]; then
  ver=$(cat ${VM_DS_PATH}/plugin.json)
  if [ -n "$ver" ]; then
    exit
  fi
fi

echo "Installing datasources..."
# shellcheck disable=SC2115
rm -rf ${VL_DS_PATH}/* || true
mkdir -p ${VL_DS_PATH}

VL_VERSION=$(curl -s "https://api.github.com/repos/VictoriaMetrics/victorialogs-datasource/releases/latest" | grep -E '"tag_name": "v[0-9.]+' | grep -oE '[0-9.]+')
wget --output-document=${PLUGIN_PATH}/plugin.tar.gz "https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v${VL_VERSION}/victorialogs-datasource-v${VL_VERSION}.tar.gz"
tar -xzf ${PLUGIN_PATH}/plugin.tar.gz -C ${VL_DS_PATH}
echo "VictoriaLogs datasource has been installed."
rm ${PLUGIN_PATH}/plugin.tar.gz

# shellcheck disable=SC2115
rm -rf ${VM_DS_PATH}/* || true
mkdir -p ${VM_DS_PATH}

VM_VERSION=$(curl -s "https://api.github.com/repos/VictoriaMetrics/grafana-datasource/releases/latest" | grep -E '"tag_name": "v[0-9.]+' | grep -oE '[0-9.]+')
wget --output-document=${PLUGIN_PATH}/plugin.tar.gz "https://github.com/VictoriaMetrics/grafana-datasource/releases/download/v${VM_VERSION}/victoriametrics-datasource-v${VM_VERSION}.tar.gz"
tar -xzf ${PLUGIN_PATH}/plugin.tar.gz -C ${VM_DS_PATH}
echo "VictoriaMetrics datasource has been installed."
rm ${PLUGIN_PATH}/plugin.tar.gz
