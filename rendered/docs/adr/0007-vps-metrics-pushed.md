# ADR 0007: VPS metrics pushed by a local vmagent, every listener on loopback

Status: accepted (2026-10-07)

## Context

The VPS is the only public host and had no metrics: HAProxy's drops, the tailnet
path to the service VMs, and the VPS's own health were invisible. The obvious
alternative, scraping it from secsvcs over the tailnet, needs secsvcs to open
connections *into* the tailnet through pfSense, which runs Tailscale in SNAT mode
(router/04 is open), would bind a listener on `tailscale0` that HAProxy's start
depends on, and would be thrown away once the VPS ran the same agents as the VMs.
observability/04 has the full comparison.

## Decision

- The VPS runs the same `vmagent` and Fluent Bit quadlets as the container VMs, plus
  `node_exporter` as a quadlet, all with `Network=host`. Podman creates no network, so
  netavark adds no nftables rules on the public host.
- Everything they scrape listens on `127.0.0.1`: HAProxy's built-in Prometheus exporter
  on `:8405`, Headscale on `:9090`, node_exporter on `:9100`, vmagent and Fluent Bit's
  own metrics, and tailscaled's client metrics at `100.100.100.100`.
- vmagent remote-writes to `metrics.SITE` and Fluent Bit to `logs.SITE`, both pinned to
  secsvcs in the VPS's `/etc/hosts` so the traffic takes the tailnet instead of
  looping through HAProxy's public frontend. ufw already allows that outbound path.
  vmagent's 1 GiB disk queue covers a tailnet or secsvcs outage.
- HAProxy's backend servers get no `check`: each backend has one server, so a health
  check buys no failover and a false DOWN would cut traffic. Unreachable VMs show up
  as `haproxy_backend_connection_errors_total`.
- A pushing host can't raise `up == 0`, so `VpsMetricsAbsent` alerts on silence, and
  the dead-man checker on the VPS (observability/10) covers the opposite direction.

## Consequences

- One install path for every service on the VPS, the same secrets pipeline (`age` +
  `secret_update.sh vpnsvcs`), and the image updater will cover it.
- Podman and its CVE stream now live on the edge host. Mitigations: no network, no
  published ports, `NoNewPrivileges`, loopback binds, `ss -ltnp` and `nft list ruleset`
  checked at install.
- About 30 MB of RAM and 400 MB of disk on the 1 GB Nanode (observability/08).
