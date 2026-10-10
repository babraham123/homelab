# ADR 0007: VPS metrics pushed by a local vmagent

Status: accepted (2026-10-07, networking revised 2026-10-10)

## Context

The VPS is the only public host and had no metrics: HAProxy's drops, the tailnet path to the service
VMs, and the VPS's own health were invisible. The obvious alternative, scraping it from secsvcs over
the tailnet, needs secsvcs to open connections *into* the tailnet through pfSense, which runs
Tailscale in SNAT mode (router/04 is open), would bind a listener on `tailscale0` that HAProxy's
start depends on, and would be thrown away once the VPS ran the same agents as the VMs.
observability/04 has the full comparison.

## Decision

- The VPS is set up like the container VMs: the Podman guide, a `net.network` bridge
  (`vpnsvcs.container_subnet`), the shared `vmagent` and Fluent Bit quadlets, and node_exporter as a
  host binary. Nothing is published.
- The host services vmagent scrapes listen on the bridge gateway (`<subnet>.1`): HAProxy's built-in
  Prometheus exporter on `:8405`, Headscale on `:9090`, and node_exporter on `:9100` (all
  interfaces, as on the VMs). ufw lets only vmagent's `<subnet>.7` reach them.
  `net.ipv4.ip_nonlocal_bind` lets HAProxy and Headscale bind the gateway at boot, before the first
  container creates the bridge. tailscaled's client metrics at `100.100.100.100` are routed out
  `tailscale0` from the container.
- vmagent remote-writes to `metrics.SITE` and Fluent Bit to `logs.SITE`, both pinned to secsvcs in
  the VPS's `/etc/hosts` (Podman copies it into the containers) so the traffic takes the tailnet
  instead of looping through HAProxy's public frontend. vmagent's 1 GiB disk queue covers a tailnet
  or secsvcs outage.
- HAProxy's backend servers get no `check`: each backend has one server, so a health check buys no
  failover and a false DOWN would cut traffic. Unreachable VMs show up as
  `haproxy_backend_connection_errors_total`.
- A pushing host can't raise `up == 0`, so `VpsMetricsAbsent` alerts on silence, and the dead-man
  checker on the VPS (observability/10) covers the opposite direction.

## Considered

- **Host networking with loopback listeners** (the first version): no bridge and no netavark rules,
  but every shared template needed a `Network=host` branch, Fluent Bit a VPS copy of its config,
  node_exporter a quadlet of its own, and the VPS a guide of its own. The VPS's firewall is ufw like
  the VMs', which the Podman guide already reconciles with netavark, so the bridge costs little.

## Consequences

- One install path and one guide for every container node, the same secrets pipeline (`age` +
  `secret_update.sh vpnsvcs`), and the image updater covers the VPS.
- Podman and its CVE stream now live on the edge host, plus a bridge and netavark's rules.
  Mitigations: no published ports, `NoNewPrivileges`, ufw's default deny with per-port allows from
  `<subnet>.7`, and `ss -ltnp` and an external port scan checked at install.
- About 30 MB of RAM and 400 MB of disk on the 1 GB Nanode (observability/08).
