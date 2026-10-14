# 06. vpnsvcs bandwidth by class and subdomain

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-13
Blocked by: 04

## Problem

Linode charges outbound transfer against the plan's monthly pool. TURN adds a
bandwidth-heavy workload to the VPS. Today nobody can see how many bytes the VPS moves,
or whether they come from:

- the public funnel;
- DERP;
- TURN;
- anything else.

## Change

1. **Interface totals.** node_exporter (pushed by vmagent, ADR 0007) already gives
   `node_network_{receive,transmit}_bytes_total{device=~"eth0|tailscale0"}`.
2. **By traffic class.** An `nftables` table `homelab_acct` with named counters on
   `eth0`, input and output, matched by port:
   - `https` (tcp 443), `http` (tcp 80);
   - `derp_stun` (udp 3478);
   - `wireguard` (udp 41641);
   - `turn` (udp/tcp 3479 and udp 49160–49200);
   - `ssh` (tcp 2202);
   - `other`: a final catch-all counter.

   Implementation:
   - Install from a `bandwidth_counters` case in `src/nodes/vpnsvcs/install_svcs.sh.j2`.
     Use a separate table so ufw's own rules stay untouched.
   - A 1-minute systemd timer runs a stdlib-Python script. It turns
     `nft -j list counters table inet homelab_acct` into
     `vpnsvcs_bytes_total{class,direction}` in node_exporter's textfile directory
     (`/var/lib/node_exporter/textfile_collector`).
   - Compare `nft list ruleset` before and after.
3. **By subdomain.** HAProxy (`src/services/haproxy/haproxy.cfg.j2`):
   - **Capture the name.**
     - `https_all`: `tcp-request content capture req.ssl_sni len 64`.
     - `http_all`: `http-request capture req.hdr(host) len 64`.
   - **Log format.** A `log-format` on both frontends that ends in `sni=<capture> up=%U down=%B`.
     The `%U`/`%B` byte counts arrive when the connection closes, so long-lived
     WebSocket and DERP connections are counted late. That's acceptable.
   - **Shipping.** fluent-bit on vpnsvcs ships the journal of units tagged by
     `base/debian/add_homelab_tag.sh` to VictoriaLogs; tag `haproxy.service` if it isn't.
   - **Grafana panel.** A VictoriaLogs query like:

     ```text
     _stream:{unit="haproxy.service"} | extract "sni=<sni> up=<up> down=<down>"
       | stats by (sni) sum(down) as down, sum(up) as up
     ```

     `vpn.SITE` is Headscale control + DERP.
4. **Dashboard** `src/services/grafana/dashboards/vpnsvcs_bandwidth.json`:
   - billable egress, 30-day rolling, against the plan's transfer pool;
   - stacked rate by class;
   - top subdomains.

   Panel notes should explain the double counting (spec, "Bandwidth on vpnsvcs").
5. **Alert** in `src/services/vmalert/configs/vps.yml`: `VpsTransferHigh` when
   `increase(node_network_transmit_bytes_total{device="eth0",host="vpnsvcs"}[30d])`
   exceeds 80% of `site.vps_transfer_bytes`. That's a new var: the Linode plan's
   monthly pool.
6. **Docs:** `docs/services.md` observability section.

## Acceptance

- The class counters add up to within 2% of node_exporter's `eth0` totals over an hour.
- Streaming one camera off-VPN for 10 minutes shows up under `turn` and nowhere else.
- Loading the Frigate UI from mobile data shows `nvr.SITE` bytes in the subdomain panel.
- `ss -ltnp` shows no new listeners.

## Comments
