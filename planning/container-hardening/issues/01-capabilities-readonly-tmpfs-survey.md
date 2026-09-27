# 01. Survey: DropCapability, ReadOnly, Tmpfs and UserNS=auto for every container

Status: ready-for-agent
Type: research
Repo: homelab
Source: review finding 15

## Scope

Rootless is out (maintainer decision; it would replace the static-IP bridge model).
Containers stay rootful. Evaluate **four** directives for **each** of the 31 quadlets:

| Directive | What it buys | How to find the right value |
|---|---|---|
| `DropCapability=ALL` + minimal `AddCapability=` | shrinks what root-in-container can do | `podman inspect --format '{{.EffectiveCaps}}'`, then start with `ALL` dropped and add back one at a time until healthy |
| `ReadOnly=true` | image layers immutable at runtime | start read-only, read the first write failure, add a `Volume`/`Tmpfs` for that path, repeat |
| `Tmpfs=/tmp`, `/run`, app-specific (`/var/cache/nginx`, …) | the writable scratch `ReadOnly` needs, without a persistent volume | from the `ReadOnly` failures |
| `UserNS=auto` | root inside ≠ root on the VM | works when volume ownership can be remapped: check against `grafana` 472:0, `olive_tin` 1000, `postgres` 70:70, `lldap` currently `UID=0` |

## Task

Produce `docs/guides/container_hardening.md`: one row per container with the four
columns above filled in as *applied* / *blocked by X* / *n/a*, plus the resulting
directive block to paste into the quadlet. Then a follow-up issue per node applies them
(one service per commit so a regression is bisectable; Traefik and Postgres last).

Known starting points: Traefik already has `AddCapability=CAP_NET_BIND_SERVICE`;
Postgres's entrypoint needs `CHOWN,SETUID,SETGID,DAC_OVERRIDE`; most single-binary Go
services (vmagent, vmalert, alertmanager, ntfy-alertmanager, gatus, go2rtc) need no
capabilities and tolerate `ReadOnly` with only their data volume writable.

Expected easy wins: traefik, vmagent, vmalert, alertmanager, ntfy-alertmanager,
victoriametrics/victorialogs (write only to their storage volume), gatus, fluentbit,
node_exporter-like exporters, go2rtc, isso, nginx (needs `Tmpfs=/var/cache/nginx`
`/run`). Expected hard cases: home_assistant, esphome, archivebox, zigbee2mqtt
(serial device), guacd.

## Acceptance

- Every one of the 31 containers has a row with all four columns decided (applied /
  blocked-by / n/a) and a tested directive block.

## Comments
