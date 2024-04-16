#!/usr/bin/env bash
# /etc/opt/grafana/vm_download.sh
set -ex

VL_DS_PATH='/var/lib/grafana/plugins/victorialogs-datasource'
VM_DS_PATH='/var/lib/grafana/plugins/victoriametrics-datasource'
PLUGIN_PATH='/var/lib/grafana/plugins'

if [[ -f ${VM_DS_PATH}/plugin.json ]]; then
    ver=$(cat ${VM_DS_PATH}/plugin.json)
    if [[ ! -z "$ver" ]]; then
    exit
    fi
fi

echo "Installing datasources..."
# shellcheck disable=SC2115
rm -rf ${VL_DS_PATH}/* || true
mkdir -p ${VL_DS_PATH}

LATEST_VERSION=$(curl https://api.github.com/repos/VictoriaMetrics/victorialogs-datasource/releases/latest | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
curl -L https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/${LATEST_VERSION}/victorialogs-datasource-${LATEST_VERSION}.tar.gz -o ${PLUGIN_PATH}/plugin.tar.gz && \
tar -xzf ${PLUGIN_PATH}/plugin.tar.gz -C ${VL_DS_PATH}
echo "VictoriaLogs datasource has been installed."
rm ${PLUGIN_PATH}/plugin.tar.gz

# shellcheck disable=SC2115
rm -rf ${VM_DS_PATH}/* || true
mkdir -p ${VM_DS_PATH}

LATEST_VERSION=$(curl https://api.github.com/repos/VictoriaMetrics/grafana-datasource/releases/latest | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
curl -L https://github.com/VictoriaMetrics/grafana-datasource/releases/download/${LATEST_VERSION}/grafana-datasource-${LATEST_VERSION}.tar.gz -o ${PLUGIN_PATH}/plugin.tar.gz && \
tar -xzf ${PLUGIN_PATH}/plugin.tar.gz -C ${VM_DS_PATH}
echo "VictoriaMetrics datasource has been installed."
rm ${PLUGIN_PATH}/plugin.tar.gz
