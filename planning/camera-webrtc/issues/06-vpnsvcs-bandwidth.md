# 06. vpnsvcs bandwidth: totals and DERP estimate

Status: ready-for-human
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
   exceeds 80% of `vps_mb_limit`. That's a new var: the Linode plan's
   monthly pool.
6. **Docs:** `docs/services.md` observability section (the dashboard and the
   derivation).

## Acceptance

- The dashboard's 30-day egress matches Linode's transfer page within 5%.
- Forcing one tailnet client onto DERP and copying 1 GB through it raises `derp` by
  about 1 GB and leaves `tailnet` flat.
- `VpsTransferHigh` fires in vmalert with `vps_mb_limit` temporarily set low.
- `ss -ltnp` shows no new listeners.

## Comments

2026-10-16: scope cut. TURN is gone (04, wontfix), so the nftables per-port counters and
the VictoriaLogs subdomain panel are dropped. The interface totals give the DERP
estimate, and a laptop script answers the per-subdomain question when needed.

- 2026-11-01: per-subdomain accounting dropped (maintainer): the laptop script and its acceptance
  line are removed. HAProxy keeps logging SNI and bytes per connection (item 3), so a LogsQL query
  can still answer it ad hoc. Left: the dashboard, `VpsTransferHigh` with `vps_mb_limit`,
  and the docs.

2026-11-01: items 4-6 in. The "VPS bandwidth" dashboard (`vpnsvcs_bandwidth.json`);
`VpsTransferHigh` in `vps.yml`; `vps_mb_limit` in `vars.template.yml`;
`docs/services.md`, `docs/maintenance.md`, and the bytes-per-SNI LogsQL query in `docs/queries.md`.

- The pool reaches the alert and the dashboard as a series, `homelab_vps_transfer_pool_bytes`,
  recorded by a new templated rule file, `src/services/vmalert/configs/plans.yml.j2`. Like
  `homelab_isp_plan_bits_per_second`, one value feeds both, and neither `vps.yml` (Go templates
  in its annotations) nor the dashboards (Grafana JSON) need Jinja. A dashboard constant would
  have put the real value in a tracked file.
- Item 2's derivation doesn't hold on live data. `tailscale0` rx + tx is larger than `eth0` tx in
  a typical hour, so `derp` clamps to 0: much of `tailscale0` rx ends on the VPS (acks and
  replies to the vmagent/Fluent Bit pushes, net_probe's nightly iperf3 upload) and never goes
  out `eth0`. The dashboard instead stacks `eth0` tx as `tailnet` (`tailscale0` tx), `derp +
  headscale` and `funnel` (HAProxy's `haproxy_backend_bytes_out_total` for the `vpn.SITE`
  backends and the `*svcs` proxies: bytes to clients), and `other` (the rest: WireGuard and
  TCP/IP headers, SSH, apt). Still no new collector. Over the last week HAProxy's Headscale
  backend counter and the log's `vpn.SITE` down agreed within about 20%; the log counts a
  connection only when it closes.
- The 30-day window needs `retention.metric_days` >= 30 (the template's example is 14).

Apply:

```bash
# 1. Add the plan's pool to the real vars.yml, top level:
#    vps_mb_limit: <plan's monthly transfer in MB>
# 2. Deploy secsvcs, then install the rules and dashboards
tools/deploy_src.sh secsvcs
ssh autoadmin@secsvcs install_vmalert
ssh autoadmin@secsvcs install_grafana
```

Verify (the acceptance checks):

```bash
# The pool series exists, and the alert loaded
curl -u "$VM_AUTH" https://metrics.SITE/api/v1/query --data-urlencode 'query=homelab_vps_transfer_pool_bytes'
#    vmalert.SITE: group vps lists VpsTransferHigh, group plans records the pool
# 30-day egress: the dashboard's "Egress, last 30 days" vs Linode's transfer page, within 5%
# DERP: force one tailnet client onto DERP (tailscale debug ... or block UDP), copy 1 GB through
#    it; "derp + headscale" rises by about 1 GB and "tailnet" stays flat
# Alert: set vps_mb_limit low (below the 30-day egress), redeploy and
#    install_vmalert; VpsTransferHigh goes pending, then fires after 1h. Restore the value.
# No new listeners on the VPS
ssh manualadmin@vpnsvcs sudo ss -ltnp
```
