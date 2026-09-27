# 02. Survey: which containers support a HealthCmd, and with what

Status: ready-for-agent
Type: research
Repo: homelab
Source: review finding 16

## Task

For each quadlet, record the health endpoint/command, whether the image ships a client
to call it (`curl`/`wget`/none — distroless and `scratch` images have neither), and the
resulting `HealthCmd=`. Commit as a column in `docs/guides/container_hardening.md`.

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
`HealthOnFailure=kill` (so `Restart=on-failure` restarts a hung service). Also propose a
vmalert rule on `podman` health state once a Podman exporter exists (observability/01
notes this).

## Acceptance

- Table complete; follow-up per-node issue applies the checks.

## Comments
