# 01. Pin container images and decide the AutoUpdate policy

Status: wontfix
Type: task
Repo: homelab
Source: review finding 9 — no explicit response received; flagged for decision

## Problem

16 of 31 quadlets use `:latest`/`:stable`, and 30 of 31 set `AutoUpdate=registry`. If
`podman-auto-update.timer` is enabled, Authelia, LLDAP, Grafana, Home Assistant,
Zigbee2MQTT, Mosquitto and ntfy take unattended upgrades. Podman only rolls back when the
unit fails to *start*; a container that starts broken (config-schema change) takes SSO
down and there is no record of last week's working tag.

## Proposed change

- Pin every `Image=` to `name:tag@sha256:...` (`src/pve1/lookup_docker_tag.sh` already
  exists to help find tags).
- Remove `AutoUpdate=registry` (or keep it only on images you genuinely don't care
  about) and document the manual upgrade procedure in `docs/maintenance.md` (fills one of
  its TODOs).
- Optional: Renovate with a regex manager for `Image=` lines in `*.container.j2` so tag
  bumps arrive as PRs. Skip if you'd rather upgrade by hand a few times a year.

## Open question for the maintainer

Your list responded to every other finding but not this one (item 9 in your list was
about Home Assistant). Confirm: pin everything? keep AutoUpdate anywhere?

## Comments

- 2026-09-21 maintainer: leave as `needs-triage`; there is a separate plan for image
  management. Do not action from this ticket.
- 2026-09-26: superseded by image-updater/ (`notes/image-updater-design.md`):
  scanned `localhost/` images with `AutoUpdate=local` instead of pinning.
