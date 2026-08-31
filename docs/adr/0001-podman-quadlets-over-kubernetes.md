# ADR 0001: Podman quadlets + systemd instead of Kubernetes or Docker Compose

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

~30 containerized services run across three Debian VMs, operated by one person. The
requirements are lifecycle management, restart-on-failure, dependency ordering, and
log aggregation. Docker Compose needs a daemon and has second-class systemd
integration; k3s/k8s brings control planes, CNI plugins, and YAML sprawl that a
single-operator homelab never amortizes.

## Decision

Run every container as a Podman quadlet: `.container`, `.volume`, and `.network`
unit files in `/etc/containers/systemd/`, generated into real systemd services by
`daemon-reload`. Rootful containers, static IPs per container on a per-VM bridge
network — no service discovery layer at all. Operations are plain systemd:
`systemctl restart <svc>`, `journalctl -eu <svc>`.

## Consequences

- Near-zero learning curve on top of systemd knowledge; no orchestrator to patch.
- Full systemd semantics (After=, Requires=, restart policies) for free.
- Static IPs make DNS, Traefik routes, and scrape configs deterministic — the render
  pipeline checks for duplicate IPs at build time.
- No health-check orchestration or rolling updates; a restart is brief downtime.
- Scales fine at ~30 services; would strain at 10×.
