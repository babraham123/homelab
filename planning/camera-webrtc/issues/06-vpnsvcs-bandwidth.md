# 06. vpnsvcs bandwidth: totals and DERP estimate

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; scope cut 2026-10-16

## Problem

Linode charges outbound transfer against the plan's monthly pool. Nobody can see how close
the VPS is to it, or how much of it is DERP relaying versus the public funnel.

## Change

1. **Interface totals.** node_exporter (pushed by vmagent, ADR 0007) already gives
   `node_network_{receive,transmit}_bytes_total{device=~"eth0|tailscale0"}`. No new
   collector.
2. **DERP estimate, derived from those totals:**

   ```text
   tailnet = rate(tailscale0 rx) + rate(tailscale0 tx)
   derp    = clamp_min(rate(eth0 tx) - tailnet, 0)
   ```

   Why it works:
   - Every funnel byte crosses `tailscale0` once and leaves `eth0` once: requests go out
     to home, and responses go out to the client through HAProxy's TLS passthrough.
     Backups and vmagent/fluent-bit pushes behave the same way.
   - DERP terminates on Headscale behind HAProxy (`vpn.SITE`) and never touches
     `tailscale0`.

   `derp` overstates DERP by WireGuard's per-packet overhead (about 5% of `tailscale0`
   tx), plus SSH, Headscale control and apt, which are small on tx. Accurate enough to
   tell whether DERP or the funnel is spending the pool.
3. **HAProxy logs SNI and bytes.** Done (2026-10-16): `https_all` in
   `src/services/haproxy/haproxy.cfg.j2` logs one tcplog line per connection at close,
   ending in `up=%U down=%B sni=<name>`. Only `[a-z0-9.-]` SNIs are captured (others log
   `-`), and the SNI is last, so a client can't inject into the line or shadow the byte
   fields. :80 isn't logged this way; it carries only redirects and ACME. Deploy with
   the `haproxy` case, which runs `haproxy -c` first.

   Byte counts arrive when a connection closes, so long-lived DERP and WebSocket
   connections count in the window they close in. `haproxy.service` is tagged, so
   fluent-bit ships the lines to VictoriaLogs (`retention.log_days`, 14).
4. **Dashboard** `src/services/grafana/dashboards/vpnsvcs_bandwidth.json`:
   - billable egress (`eth0` tx), 30-day rolling, against the plan's transfer pool;
   - stacked `eth0` tx rate split into `tailnet` and `derp`, from item 2.

   Panel notes explain the derivation and its overstatement.
5. **Alert** in `src/services/vmalert/configs/vps.yml`: `VpsTransferHigh` when
   `increase(node_network_transmit_bytes_total{device="eth0",host="vpnsvcs"}[30d])`
   exceeds 80% of `site.vps_transfer_bytes`. That's a new var: the Linode plan's
   monthly pool.
6. **Docs:** `docs/services.md` observability section (the dashboard and the
   derivation).

## Acceptance

- The dashboard's 30-day egress matches Linode's transfer page within 5%.
- Forcing one tailnet client onto DERP and copying 1 GB through it raises `derp` by
  about 1 GB and leaves `tailnet` flat.
- `VpsTransferHigh` fires in vmalert with `site.vps_transfer_bytes` temporarily set low.
- `ss -ltnp` shows no new listeners.

## Comments

2026-10-16: scope cut. TURN is gone (04, wontfix), so the nftables per-port counters and
the VictoriaLogs subdomain panel are dropped. The interface totals give the DERP
estimate, and a laptop script answers the per-subdomain question when needed.

- 2026-11-01: per-subdomain accounting dropped (maintainer): the laptop script and its acceptance
  line are removed. HAProxy keeps logging SNI and bytes per connection (item 3), so a LogsQL query
  can still answer it ad hoc. Left: the dashboard, `VpsTransferHigh` with `site.vps_transfer_bytes`,
  and the docs.
