# shellcheck shell=bash
# Install steps shared by the container VMs' install_svcs.sh, sourced after lib.sh:
#   # shellcheck source=src/base/podman/svcs_lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/svcs_lib.sh"
# Kept out of lib.sh because only the Podman hosts run Traefik and Fluent Bit. Paths are
# relative to $rendered, where install_svcs.sh runs. The callers still install the quadlets
# and restart the units, so each case reads as the full install of its service.

# Usage: install_traefik_config NODE; NODE's routes plus the config every node shares
install_traefik_config() {
  mkdir -p /etc/opt/traefik/certificates
  # Emptied first so routes deleted from the repo stop being served
  rm -rf /etc/opt/traefik/config/dynamic/*
  install -D -m 644 -t /etc/opt/traefik/config/dynamic "nodes/$1/traefik/"*.yml services/traefik/dynamic/*.yml
  install -D -m 644 services/traefik/static.yml /etc/opt/traefik/config/static/traefik.yml
  rm -rf /etc/opt/traefik/plugins-local
  cp -r services/traefik/plugins-local /etc/opt/traefik/
}

# Usage: install_fluentbit_config [CONFIG]; CONFIG defaults to the pipeline the nodes share
install_fluentbit_config() {
  install -D -m 644 "${1:-services/fluentbit/fluentbit.yaml.j2}" /etc/opt/fluentbit/config.yaml.j2
  install -D -m 644 -t /etc/opt/fluentbit services/fluentbit/journald.lua
  install -D -m 644 base/debian/journald.conf /etc/systemd/journald.conf.d/homelab.conf
  systemctl restart systemd-journald
}
