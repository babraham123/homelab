#!/bin/sh
# Downloads the VictoriaMetrics and VictoriaLogs plugins for Grafana. Runs on startup.
# Usage:
#   /etc/opt/grafana/vm_download.sh
# https://github.com/VictoriaMetrics/victorialogs-datasource?tab=readme-ov-file

set -eu

plugin_path="/var/lib/grafana/plugins"
vl_ds_path="${plugin_path}/victorialogs-datasource"
vm_ds_path="${plugin_path}/victoriametrics-datasource"

VL_VERSION=$(curl -s "https://api.github.com/repos/VictoriaMetrics/victorialogs-datasource/releases/latest" | grep -E '"tag_name": "v[0-9.]+' | grep -oE '[0-9.]+')
VM_VERSION=$(curl -s "https://api.github.com/repos/VictoriaMetrics/victoriametrics-datasource/releases/latest" | grep -E '"tag_name": "v[0-9.]+' | grep -oE '[0-9.]+')

vl_plugin_ver=$(cat ${vl_ds_path}/victorialogs-datasource/plugin.json | grep version | sed -r 's/^\s*"version": "([^"]+)",$/\1/' || true)
vm_plugin_ver=$(cat ${vm_ds_path}/victoriametrics-datasource/plugin.json | grep version | sed -r 's/^\s*"version": "([^"]+)",$/\1/' || true)
if [ "$vl_plugin_ver" = "$VL_VERSION" ] && [ "$vm_plugin_ver" = "$VM_VERSION" ]; then
  echo "VictoriaLogs (${VL_VERSION}) and VictoriaMetrics (${VM_VERSION}) datasources are up to date."
  exit
fi

echo "Downloading datasources..."

wget --output-document=${plugin_path}/plugin.tar.gz "https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v${VL_VERSION}/victorialogs-datasource-v${VL_VERSION}.tar.gz"
# shellcheck disable=SC2115
rm -rf ${vl_ds_path} || true
mkdir -p ${vl_ds_path}
tar -xzf ${plugin_path}/plugin.tar.gz -C ${vl_ds_path}
echo "VictoriaLogs datasource version ${VL_VERSION} has been installed."
rm ${plugin_path}/plugin.tar.gz

wget --output-document=${plugin_path}/plugin.tar.gz "https://github.com/VictoriaMetrics/victoriametrics-datasource/releases/download/v${VM_VERSION}/victoriametrics-datasource-v${VM_VERSION}.tar.gz"
# shellcheck disable=SC2115
rm -rf ${vm_ds_path} || true
mkdir -p ${vm_ds_path}
tar -xzf ${plugin_path}/plugin.tar.gz -C ${vm_ds_path}
echo "VictoriaMetrics datasource verison ${VM_VERSION} has been installed."
rm ${plugin_path}/plugin.tar.gz
