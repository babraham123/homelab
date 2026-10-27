#!/bin/bash
# Renders FILE.j2 into FILE, next to it, for this node: the second pass of a file the
# container VMs share. The template gets the node's src/nodes.jinja host_vars:
#   node:     the node name, which is the hostname
#   subnet:   its container_subnet from vars.yml
#   services: its inventory services, e.g. services.traefik.subdomain
# Usage:
#   src/base/podman/render_host.sh FILE
# Ref:
# https://github.com/kpfleming/jinjanator

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

file=${1:?usage: $0 FILE}
rm -f "$file"

if [ ! -f "$file.j2" ]; then
  die "file template $file.j2 does not exist"
fi

case $(hostname -s) in
  homesvcs)
    vars='{"node": "homesvcs", "services": {"crowdsec_appsec": {"dirs": ["services/crowdsec"], "shared": true, "upstream": "docker.io/crowdsecurity/crowdsec:latest"}, "fluentbit": {"shared": true, "upstream": "docker.io/fluent/fluent-bit:5.1"}, "home_assistant": {"subdomain": "home", "upstream": "docker.io/homeassistant/home-assistant:2026.10", "uptime": "home assistant", "uptime_tier": 1}, "mosquitto": {"upstream": "docker.io/library/eclipse-mosquitto:latest"}, "traefik": {"admin": true, "shared": true, "subdomain": "homeproxy", "upstream": "docker.io/library/traefik:v3.7", "uptime": "traefik homesvcs", "uptime_tier": 1}, "vmagent": {"dirs": ["services/victoriametrics"], "shared": true, "upstream": "docker.io/victoriametrics/vmagent:latest"}, "zigbee2mqtt": {"subdomain": "zigbee", "upstream": "ghcr.io/koenkk/zigbee2mqtt:latest", "uptime": "zigbee2mqtt"}}, "subnet": "10.12.0"}'
    ;;
  secsvcs)
    vars='{"node": "secsvcs", "services": {"alertmanager": {"admin": true, "subdomain": "alert", "update_last": true, "upstream": "docker.io/prom/alertmanager:latest", "uptime": "alertmanager"}, "authelia": {"subdomain": "auth", "upstream": "docker.io/authelia/authelia:4.39", "uptime": "authelia", "uptime_conditions": ["[BODY].status == OK"], "uptime_path": "/api/health", "uptime_tier": 1}, "crowdsec": {"upstream": "docker.io/crowdsecurity/crowdsec:latest"}, "crowdsec_appsec": {"dirs": ["services/crowdsec"], "shared": true, "upstream": "docker.io/crowdsecurity/crowdsec:latest"}, "fluentbit": {"shared": true, "upstream": "docker.io/fluent/fluent-bit:5.1"}, "gatus": {"subdomain": "uptime", "upstream": "docker.io/twinproduction/gatus:latest"}, "grafana": {"subdomain": "graph", "upstream": "docker.io/grafana/grafana-oss:latest", "uptime": "grafana", "uptime_tier": 1}, "lldap": {"admin": true, "subdomain": "ldap", "upstream": "docker.io/lldap/lldap:stable"}, "ntfy": {"subdomain": "push", "update_last": true, "upstream": "docker.io/binwiederhier/ntfy:latest", "uptime": "ntfy health check", "uptime_path": "/v1/health", "uptime_tier": 1}, "ntfy-alertmanager": {"dirs": ["services/alertmanager"], "subdomain": "ntfy-alertmanager", "update_last": true, "upstream": "docker.io/xenrox/ntfy-alertmanager:latest"}, "ntfy_idp_push": {"admin": true, "subdomain": "idp-push", "upstream": "ghcr.io/babraham123/ntfy-idp-push:latest", "uptime": "ntfy-idp-push", "uptime_path": "/healthz"}, "olive_tin": {"admin": true, "subdomain": "command", "upstream": "docker.io/jamesread/olivetin:latest-3k", "uptime": "olive_tin"}, "postgres": {"upstream": "docker.io/library/postgres:18-alpine"}, "traefik": {"admin": true, "shared": true, "subdomain": "secproxy", "update_last": true, "upstream": "docker.io/library/traefik:v3.7", "uptime": "traefik secsvcs", "uptime_tier": 1}, "vaultwarden": {"admin": true, "subdomain": "vault", "upstream": "docker.io/vaultwarden/server:latest", "uptime": "vaultwarden", "uptime_path": "/alive", "uptime_tier": 1}, "victorialogs": {"subdomain": "logs", "upstream": "docker.io/victoriametrics/victoria-logs:latest", "uptime": "victorialogs"}, "victoriametrics": {"subdomain": "metrics", "update_last": true, "upstream": "docker.io/victoriametrics/victoria-metrics:latest", "uptime": "victoriametrics"}, "vmalert": {"admin": true, "subdomain": "vmalert", "update_last": true, "upstream": "docker.io/victoriametrics/vmalert:latest", "uptime": "vmalert"}}, "subnet": "10.10.0"}'
    ;;
  vpnsvcs)
    vars='{"node": "vpnsvcs", "services": {"crowdsec_firewall_bouncer": {"dirs": ["services/crowdsec"]}, "deadman": {}, "fail2ban": {}, "fluentbit": {"shared": true, "upstream": "docker.io/fluent/fluent-bit:5.1"}, "geoip_generator": {"build": "geoip_generator"}, "haproxy": {}, "headscale": {}, "tailscaled": {}, "vmagent": {"dirs": ["services/victoriametrics"], "shared": true, "upstream": "docker.io/victoriametrics/vmagent:latest"}}, "subnet": "10.13.0"}'
    ;;
  websvcs)
    vars='{"node": "websvcs", "services": {"bookmark_handoff": {"build": "bookmark_handoff"}, "calliope": {"build": "calliope"}, "car_ingest": {"build": "car_ingest"}, "copyparty": {"subdomain": "files", "upstream": "docker.io/copyparty/ac:latest", "uptime": "copyparty"}, "crowdsec_appsec": {"dirs": ["services/crowdsec"], "shared": true, "upstream": "docker.io/crowdsecurity/crowdsec:latest"}, "finance_exporter": {"build": "finance_exporter"}, "fluentbit": {"shared": true, "upstream": "docker.io/fluent/fluent-bit:5.1"}, "homepage": {"subdomain": "dash", "upstream": "ghcr.io/gethomepage/homepage:latest", "uptime": "homepage", "uptime_tier": 1}, "isso": {"subdomain": "comment", "upstream": "ghcr.io/isso-comments/isso:release"}, "linkding": {"subdomain": "archive", "upstream": "docker.io/sissbruecker/linkding:latest-plus", "uptime": "linkding", "uptime_path": "/health"}, "nginx": {"subdomain": "www", "upstream": "docker.io/library/nginx:stable"}, "readeck": {"subdomain": "read", "upstream": "codeberg.org/readeck/readeck:latest", "uptime": "readeck", "uptime_path": "/api/info"}, "snapraid": {}, "storyteller": {"subdomain": "books", "upstream": "registry.gitlab.com/storyteller-platform/storyteller:web-v2", "uptime": "storyteller", "uptime_path": "/api/health"}, "traefik": {"admin": true, "shared": true, "subdomain": "webproxy", "upstream": "docker.io/library/traefik:v3.7", "uptime": "traefik websvcs", "uptime_tier": 1}, "vmagent": {"dirs": ["services/victoriametrics"], "shared": true, "upstream": "docker.io/victoriametrics/vmagent:latest"}, "yt_to_audiobook": {"build": "yt_to_audiobook"}}, "subnet": "10.11.0"}'
    ;;
esac

echo "$vars" | jinjanate --quiet --format=json -o "$file" "$file.j2"
