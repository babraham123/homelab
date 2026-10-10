# 02. Survey: which containers support a HealthCmd, and with what

Status: ready-for-agent Type: research Repo: homelab Source: review finding 16

## Task

For each quadlet, record the health endpoint/command, whether the image ships a client to call it
(`curl`/`wget`/none — distroless and `scratch` images have neither), and the resulting `HealthCmd=`.
Commit as a column in [`container_hardening.md`](../container_hardening.md).

Known starting points:

| Container | Health check | Client in image? |
|---|---|---|
| traefik | `traefik healthcheck --ping` (requires `ping:` in static config) | yes (binary) |
| postgres | `pg_isready -U postgres` | yes |
| authelia | `/app/healthcheck.sh` (ships in image) | yes |
| lldap | `/app/lldap healthcheck` | yes (binary) |
| grafana | `GET /api/health` | curl yes |
| victoriametrics / victorialogs / vmalert / vmagent | `GET /health` | check — newer images are scratch-based; may need `HealthCmd` via `wget` if present, else skip or use a `podman healthcheck` sidecar approach |
| alertmanager | `GET /-/healthy` | check |
| gatus | `GET /health` | check |
| ntfy | `GET /v1/health` | check |
| home_assistant | `GET /` (200) | curl yes |
| mosquitto | `mosquitto_sub -t '$SYS/#' -C 1 -i healthcheck` | yes |
| zigbee2mqtt / esphome / homepage / isso / nginx / go2rtc / guacamole | `GET /` on the app port | check per image |
| guacd | `nc -z localhost 4822` | check |
| fluentbit | `GET /api/v1/health` | check |
| olive_tin | `GET /` | check |

For each with a client: `HealthCmd=...`, `HealthInterval=30s`, `HealthRetries=3`,
`HealthOnFailure=kill` (so `Restart=on-failure` restarts a hung service). Also propose a vmalert
rule on `podman` health state once a Podman exporter exists (observability/01 notes this).

## Acceptance

- Table complete; follow-up per-node issue applies the checks.

## Comments

- 2026-10-10: health column and per-container blocks are in
  [`container_hardening.md`](../container_hardening.md). Health checks only on core services:
  postgres, lldap, authelia, traefik, victoriametrics, vmagent, vmalert, alertmanager,
  ntfy-alertmanager, ntfy, grafana, mosquitto (busybox `wget`/`nc` allowed). victorialogs, gatus and
  fluentbit have no client; `up` covers them. Every other service lists a candidate check but gets
  none. All checks run every 30s, kill after 3 failures. Traefik needs a loopback `ping` entrypoint
  (`127.0.0.1:8083`); Authelia needs `server.disable_healthcheck: true` to run read-only;
  alertmanager injects `alertmanager_admin_password` for its basic auth. Alerting uses systemd's
  restart counter instead of a Podman exporter: `--collector.systemd.enable-restarts-metrics` in
  `node_runner.sh` and `ServiceRestartLoop` in `homelab.yml`. Fixed alongside: isso on 8080
  throughout (was routed to 8200), wyoming-addons download from `master`. Open (test on node):
  - each `HealthCmd` through quadlet and systemd (the guide's escaping test), alertmanager's `$$`
    first
  - busybox `nc -z` in the mosquitto image
