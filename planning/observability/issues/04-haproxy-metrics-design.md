# 04. Design: get HAProxy metrics from the VPS into VictoriaMetrics

Status: resolved
Type: research
Repo: homelab
Source: review finding 21

## Options

**A. HAProxy built-in exporter, scraped over the tailnet (recommended now).**
HAProxy ≥ 2.0 ships a Prometheus exporter; no extra process. In
`src/haproxy/haproxy.cfg.j2`:

```
frontend prometheus
    mode http
    bind {{ vpn.tailscale_ip }}:8405
    http-request use-service prometheus-exporter if { path /metrics }
    no log
```

Bind only on the Tailscale interface (so it is unreachable from the internet) and add
`tcp-request connection reject if !{ src 100.64.0.0/10 }` as belt-and-braces. Then
`src/secsvcs/prometheus.yml.j2` gets a `haproxy` job targeting
`{{ vpn.tailscale_ip }}:8405` — secsvcs's VictoriaMetrics is already a mesh peer (the
VMs are HAProxy's backends over Tailscale). Five lines of config, zero new software on
the VPS. Also scrape the VPS's node_exporter the same way (the VPS has none today —
install it via `src/vpn/install_svcs.sh`, bind to the tailnet IP).

**B. Podman + vmagent on the VPS, remote-writing to VictoriaMetrics.** More moving
parts, but collects node_exporter/fluentbit locally and is the foundation for
observability/08 (containerising the VPS services). Do this *after* A, when 08 lands.

**Not recommended:** exposing `:8405` publicly behind an ACL, or a separate
`haproxy_exporter` binary (deprecated in favour of the built-in one).

## Deliverable

- Implement A. Import Grafana.com dashboard **12693** ("HAProxy 2 Full") as
  `src/grafana/dashboards/haproxy.json`, fix datasource.
- Alerts: `HaproxyDown` (`up{job="haproxy"}==0`), `HaproxyBackendDown`
  (`haproxy_backend_up == 0`), and a panel for `haproxy_frontend_denied_connections_total`
  so you can finally see how much the edge is dropping.
- Record the decision as `docs/adr/0006-haproxy-metrics-over-tailnet.md`.

## Notes

`vpn.tailscale_ip` may need adding to `vars.yml`; Traefik's `trustedIPs` already
reference the VPS by `vpn.ip`.

## Comments

- 2026-09-27: researched and resolved; see Answer. It supersedes the Deliverable above:
  option A is dropped and B is done directly in 08.

## Answer

**Recommendation: skip option A. Do option B as part of observability/08, with every VPS
metrics endpoint on loopback.** HAProxy's built-in exporter binds `127.0.0.1:8405`. A
vmagent quadlet on the VPS with `Network=host` scrapes it, plus node_exporter, Headscale
(already on `127.0.0.1:9090`), tailscaled (`100.100.100.100/metrics`) and fluent-bit. It
remote-writes to `metrics.SITE` on secsvcs over the tailnet. No new listener sits on any
interface, not even `tailscale0`. The only traffic crossing the tailnet is outbound
VPS → secsvcs:443, which the VPS's ufw rules already allow
(`docs/guides/vpn.md.j2`). vmagent's disk buffer fills any gap from a tailnet outage.

Why not A first:

- **It likely doesn't route today.** A needs secsvcs to open connections *into* the
  tailnet through pfSense. The VMs are not tailnet peers; pfSense is the only home
  node, acting as subnet router. Tailscale documents site-to-site only for Linux subnet
  routers with `--snat-subnet-routes=false`. pfSense is FreeBSD in netstack/SNAT mode,
  and router/04 (kernel routing) is `ready-for-human`.
- **It risks public ingress on boot.** With `bind <tailnet-ip>:8405`, HAProxy fails to
  start if `tailscale0` isn't up yet, which takes down :80/:443. The fix is
  `net.ipv4.ip_nonlocal_bind=1`.
- **It needs new parts.** A `vpn.tailscale_ip` var: Headscale assigns the address, and it
  changes on re-registration. A `ufw allow in on tailscale0` rule. And an ACL that doesn't
  exist yet: Headscale runs with no policy file (`policy.path` is commented out in
  `src/headscale/headscale.yaml.j2`), so the tailnet is allow-all.
- **It's throwaway.** 08 would replace it, and 08 is approved and blocked only by this
  ticket.

### Options

| | A. Pull over tailnet | **B. Local vmagent, loopback, push** | B′. B as host binaries | Public `:8405` + ACL | `haproxy_exporter` |
|---|---|---|---|---|---|
| New listener | `100.x:8405` | none off loopback | none off loopback | public IP | extra process |
| Auth / ACL | tailnet (allow-all today) + ufw + HAProxy `src` ACL | not needed (loopback) | same as B | edge ACL or basic auth | n/a |
| Traffic direction | home → VPS: new, and needs pfSense no-SNAT | VPS → secsvcs:443, already allowed | same as B | internet → VPS | n/a |
| Tailnet down | scrape gap; `up==0` fires, indistinguishable from HAProxy down | buffered on disk, then backfilled; absence alert fires | same as B | n/a | n/a |
| HAProxy boot dependency | on `tailscale0` | none | none | none | none |
| New on VPS | nothing | vmagent (08 adds node_exporter, fluent-bit) | same as B, as apt/tarball units | nothing | exporter binary |
| Repo fit | small but throwaway | matches 08 and the websvcs/homesvcs vmagent | contradicts 08's Podman decision | contradicts ADR 0002's posture | deprecated upstream |
| Verdict | drop | **do** | only if 08 is reverted | no | no |

### Corrections to the Deliverable

- **`haproxy_backend_up` doesn't exist.** It came from the old `haproxy_exporter`. The
  built-in exporter has `haproxy_backend_status{state="UP"}`, a 0/1 state-set gauge
  (`addons/promex/service-prometheus.c`).
- **The backends have no `check`.** HAProxy treats a server without `check` as always
  UP, so `HaproxyBackendDown` would never fire. Add `check` to the six VM servers.
  Health checks send PROXY v2 because the servers use `send-proxy-v2`, so Traefik
  accepts them.
- **`haproxy_frontend_denied_connections_total` stays ~0.** Every drop rule here is
  `tcp-request content` or `http-request silent-drop`, and silent-drop increments
  `denied_req` (`src/tcp_act.c`, `tcp_exec_action_silent_drop`). Graph
  `haproxy_frontend_requests_denied_total` and
  `haproxy_backend_requests_denied_total{proxy=~"silent_drop_.*"}` instead.
- **Push breaks `up == 0` as a VPS-down signal.** When the VPS or the tailnet dies, no
  samples arrive, so observability/01's `NodeDown` (`up{job=~"node_exporter.*"} == 0`)
  can't fire for the VPS. It needs an absence rule, and observability/10 relies on that
  rule for "VPS down".
- **Existing bug on every node.** `src/victoriametrics/vmagent.container.j2.j2` mounts
  `/vmagentdata` but never sets `-remoteWrite.tmpDataPath`. The default is the relative
  path `vmagent-remotewrite-data` in the container rootfs, so the buffer is lost whenever
  the container is recreated.
- **ADR 0006 is taken** by image-updater/07. Use the next free number.
- **The exporter is already installed.** Debian trixie ships HAProxy 3.0.11, built with
  `USE_PROMEX=1`. Confirm on the VPS with `haproxy -vv | grep -i prometheus`.

### Config sketch

`src/haproxy/haproxy.cfg.j2`:

```
frontend prometheus
    mode http
    bind 127.0.0.1:8405
    http-request use-service prometheus-exporter if { path /metrics }
    http-request deny
    no log

backend secsvcs_https_proxy
    mode tcp
    server secsvcs_https {{ secsvcs.ip }}:443 send-proxy-v2 check inter 10s fall 3 rise 2
# ...same `check inter 10s fall 3 rise 2` on the other five *_proxy servers
```

`src/vpn/prometheus.yml.j2` (new; installed to `/etc/opt/vmagent/` as on websvcs):

```yaml
global:
  scrape_interval: 10s
scrape_configs:
  - job_name: haproxy
    static_configs: [{targets: ['127.0.0.1:8405']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:8405'}]
  - job_name: node_exporter
    static_configs: [{targets: ['127.0.0.1:9100']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:9100'}]
  - job_name: headscale
    static_configs: [{targets: ['127.0.0.1:9090']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:9090'}]
  - job_name: tailscaled            # client metrics, tailscale >= 1.78
    static_configs: [{targets: ['100.100.100.100:80']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:tailscaled'}]
  - job_name: vmagent
    static_configs: [{targets: ['127.0.0.1:8429']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:8429'}]
  - job_name: fluentbit
    metrics_path: /api/v1/metrics/prometheus
    static_configs: [{targets: ['127.0.0.1:2020']}]
    relabel_configs: [{target_label: instance, replacement: 'vpn.{{ site.url }}:2020'}]
```

**vmagent quadlet.** Keep the one shared template `src/victoriametrics/vmagent.container.j2.j2`.
Add a `vpn)` case to `render_host.sh` that sets `subnet=""`, and branch on `subnet` in
the template. Second-pass tags need `{% raw %}` wrapping, as the `IP=` line has now.

- **All nodes** get these new flags:
  - `--remoteWrite.tmpDataPath=/vmagentdata`
  - `--remoteWrite.maxDiskUsagePerURL=1GiB`
- **The VPS branch renders to:**

```
Network=host        # host netns: reaches loopback targets and 100.100.100.100; no netavark bridge, no nftables rules
Exec=--promscrape.config="/etc/prometheus/prometheus.yml" \
     --httpListenAddr="127.0.0.1:8429" \
     --remoteWrite.url="https://metrics.{{ site.url }}/api/v1/write" \
     --remoteWrite.tmpDataPath="/vmagentdata" \
     --remoteWrite.maxDiskUsagePerURL="1GiB" \
     --remoteWrite.label="host=vpn.{{ site.url }}" \
     ...existing basicAuth / forceVMProto / naming / logger flags...
```

`--remoteWrite.label` puts the `host` label that observability/10 asks for on every VPS
series, in one place.

**Name pinning on the VPS.** Add a new `hosts` case in `src/vpn/install_svcs.sh.j2`. It
writes a managed `/etc/hosts` block that maps these names to `{{ secsvcs.ip }}`:

- `metrics.SITE`
- `logs.SITE`
- `alert.SITE`
- `push.SITE`

Why it's needed:

- **Without it, traffic hairpins through the edge.** The VPS resolves those names
  publicly to itself and loops through HAProxy's public frontend. HAProxy's own metrics
  would then travel through HAProxy, subject to the edge rate limits.
- **It covers the containers.** Host-network containers inherit the host's `/etc/hosts`.
- **observability/10 needs it too.** Its dead-man checker queries the same names over
  the tailnet.

Nothing else changes: ufw already allows `out on tailscale0 to {{ secsvcs.ip }} port
80,443`, and Traefik accepts connections from trusted IPs with or without a PROXY
header.

`src/vmalert/configs/vps.yml` (new):

```yaml
groups:
  - name: vps
    rules:
      - alert: VpsMetricsAbsent       # VPS down, tailnet down, or vmagent down
        expr: absent_over_time(up{job="node_exporter",host="vpn.{{ site.url }}"}[5m])
        for: 5m
      - alert: HaproxyDown
        expr: up{job="haproxy"} == 0
        for: 2m
      - alert: HaproxyBackendDown
        expr: haproxy_backend_status{state="UP",proxy=~".*svcs_https?_proxy"} == 0
        for: 2m
```

Buffer overflow is already covered by `PersistentQueueIsDroppingData` in
`src/vmalert/configs/vmagent.yml`.

### Failure modes (B)

| Event | Effect |
|---|---|
| Tailnet or secsvcs down | vmagent keeps scraping and buffers up to 1 GiB (days, at a few hundred series), then backfills. `VpsMetricsAbsent` fires meanwhile; Gatus also sees public ingress down. |
| HAProxy down | `HaproxyDown` fires. Node and Headscale metrics keep flowing. |
| VPS down | No data arrives. `VpsMetricsAbsent` fires. |
| Buffer full | Oldest data dropped. `PersistentQueueIsDroppingData` fires. |

### Follow-up steps (fold into observability/08)

1. **HAProxy.** Add the `prometheus` frontend on `127.0.0.1:8405` and `check` on the six
   VM servers. Verify with `haproxy -c -f` and `curl -s 127.0.0.1:8405/metrics`.
2. **Shared vmagent template.** Add `tmpDataPath` and `maxDiskUsagePerURL`, which fixes
   every node. Add the `Network=host` branch and the `vpn)` case in `render_host.sh`.
3. **VPS scrape config and installer.** Write `src/vpn/prometheus.yml.j2`. Add `vmagent`
   and `hosts` cases to `src/vpn/install_svcs.sh.j2`, alongside 08's `podman`,
   `node_exporter` and `fluentbit` cases.
4. **08's other containers** also use `Network=host` with loopback binds:
   - node_exporter: `--web.listen-address=127.0.0.1:9100`; add `--pid=host` and mount
     `/:/host:ro,rslave` with `--path.rootfs=/host`, per the upstream README;
   - fluent-bit: `http_listen: 127.0.0.1`.

   This drops 08's `net.network` prerequisite: with no netavark bridge, nftables stays
   untouched. Keep 08's `nft list ruleset` before/after check to confirm.
5. **Remote-write credential.** Decide per open question 1.
6. **Alerts.** Add `src/vmalert/configs/vps.yml`. Exclude the VPS from `NodeDown` in
   observability/01; `VpsMetricsAbsent` replaces it there.
7. **Dashboard.** Import Grafana.com 12693 as `src/grafana/dashboards/haproxy.json` and
   fix the datasource. Replace the denied-connections panel with
   `sum by (proxy) (rate(haproxy_frontend_requests_denied_total[5m]))`.
8. **Docs.**
   - `docs/services.md`: the VPS row in the host-level table and the observability
     diagram.
   - `docs/architecture.md`: remove "no containers" for vpn.
   - A new ADR at the next free number: "VPS metrics pushed by a local vmagent".
9. **Acceptance.** This replaces 08's `up{instance="vpn.SITE"}` check:
   - `up{host="vpn.SITE"} == 1` for all six jobs;
   - `ss -ltnp` on the VPS shows no new listeners off loopback;
   - stop tailscaled for 10 minutes and restart it: the series have no gap.

### For the blocked tickets

- **observability/08:** scope as above. It needs no `vpn.tailscale_ip` and no
  `net.network`.
- **restructure/06:** there's no `vpn.tailscale_ip` var and no `node_exporter_vpn` job
  to rename; job names are generic. The VPS name appears in:
  - `src/vpn/prometheus.yml.j2` (instance relabels);
  - the vmagent flag `--remoteWrite.label=host=vpn.SITE`;
  - the `vpn)` case in `render_host.sh`;
  - `VpsMetricsAbsent`'s expression;
  - any dashboard filters.

  A rename changes the `instance` and `host` label values, which starts new series.
  Either accept that break or keep the label value `vpn`. The `/etc/hosts` pin maps
  secsvcs names only, so it's unaffected.

### Open questions

1. **Remote-write credential.** Every vmagent uses the VictoriaMetrics admin password
   today. On the internet-facing VPS, that password also allows reads and
   `delete_series`. The alternative is a write-only route on secsvcs Traefik:
   - rule `Host(metrics) && Path(/api/v1/write)`;
   - a `basicAuth` middleware with a `vm-writer` user and `removeHeader: true`;
   - then the existing `vm-auth` middleware for the upstream.

   All three vmagents would switch to the writer credential. Recommended; the
   maintainer decides.
2. **Where to pin names.** `/etc/hosts` on the VPS host (one place, shared with the
   observability/10 dead-man) or `AddHost=` per quadlet? Recommended: `/etc/hosts`.
3. **Health checks change the edge.** With `check`, a backend marked DOWN drops new
   connections instead of trying them. Acceptable?
4. **Ticket split.** Keep everything in 08, or move the HAProxy config, alerts and
   dashboard into a separate observability ticket?

### Sources

- HAProxy exporter: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/prometheus/ ,
  https://github.com/haproxy/haproxy/blob/master/addons/promex/README ;
  metric names: https://github.com/haproxy/haproxy/blob/v3.0.0/addons/promex/service-prometheus.c ;
  silent-drop counters: https://github.com/haproxy/haproxy/blob/v3.0.0/src/tcp_act.c ;
  `check`: https://docs.haproxy.org/3.0/configuration.html#5.2-check
- Debian HAProxy 3.0.11 in trixie with `USE_PROMEX=1`: https://sources.debian.org/src/haproxy/ ,
  https://salsa.debian.org/haproxy-team/haproxy/-/blob/master/debian/rules
- vmagent buffering, `tmpDataPath`, `maxDiskUsagePerURL`, `remoteWrite.label`:
  https://docs.victoriametrics.com/victoriametrics/vmagent/ ; default path:
  https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/app/vmagent/remotewrite/remotewrite.go
- Tailscale site-to-site (Linux only, no SNAT): https://tailscale.com/kb/1214/site-to-site ;
  client metrics: https://tailscale.com/kb/1482/client-metrics ;
  ufw and `tailscale0`: https://tailscale.com/kb/1077/secure-server-ubuntu
- Headscale ACLs: https://headscale.net/stable/ref/acls/
- node_exporter in a container: https://github.com/prometheus/node_exporter#docker
