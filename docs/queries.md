# Metrics and log queries

Starting points for querying VictoriaMetrics (PromQL/MetricsQL) and VictoriaLogs (LogsQL), from the
vmui pages, curl ([debugging](debugging.md#observability)), Grafana's Explore, or Claude Code's MCP
servers ([guide](guides/claude_telemetry.md)). The alert rules in `src/services/vmalert/configs/`
and the dashboards in `src/services/grafana/dashboards/` hold the full set; every query below was
run against the live instances.

## Labels and fields

### Metric labels

- `host`: the bare node name (`secsvcs`, `websvcs`, `pve2`) on every scraped series, the same value
  as `hostname` on every log line, so one value filters both. It names the target, not the scraper:
  `nvidia_gpu_desktops` carries `host="gaming"` and `host="devtop"`
- `job`: the scrape job, per node in `src/nodes/<node>/prometheus.yml.j2`; `instance` is the
  scrape address, rarely useful here
- `exported_job`: the job label a pushed metric came with (`homelab_backup_*` per backup job)
- `alertname`, `alertgroup`, `alertstate`: on `ALERTS`. Groups: `backups`, `crowdsec`,
  `fluentbit`, `hosts`, `network`, `pipeline`, `scrapes`, `uptime`, `vm-health`, `vmagent`,
  `vmalert`, `vmsingle`, `vps`

| Node | Jobs |
| ---- | ---- |
| secsvcs | `authelia`, `vmalert`, `victoriametrics`, `victorialogs`, `fluentbit`, `gatus`, `crowdsec`, `crowdsec_appsec`, `ntfy`, `traefik`, `node_exporter`, `node_exporter_pve` (pve1) |
| websvcs | `vmagent`, `fluentbit`, `crowdsec_appsec`, `finance_exporter`, `traefik`, `node_exporter`, `node_exporter_pve` (pve2), `smartctl`, `nvidia_gpu`, `nvidia_gpu_desktops` (gaming, devtop) |
| homesvcs | `vmagent`, `fluentbit`, `crowdsec_appsec`, `traefik`, `node_exporter` |
| vpnsvcs | `vmagent`, `fluentbit`, `haproxy`, `crowdsec_firewall_bouncer`, `headscale`, `tailscaled`, `node_exporter` |

Metric prefixes by job: `authelia_`, `cs_` (both CrowdSec jobs; `cs_appsec_*` from the appsec
one), `fw_bouncer_`, `gatus_results_`, `haproxy_{frontend,backend,server}_`, `headscale_`,
`tailscaled_`, `ntfy_`, `traefik_`, `finance_`, `nvidia_smi_`, `smartctl_device_`, `node_`,
`vm_`/`vmagent_`/`vmalert_`/`vl_`/`fluentbit_`. Pushed by the nodes' own scripts: `homelab_*`
(backups, net probe, deploys) and `image_updater_*`.

### Log fields

Set by `src/services/fluentbit/journald.lua.j2` from the journal. Only the units in each node's
`homelab_services` reach VictoriaLogs; the rest of the journal stays on the node.

| Field | What |
| ----- | ---- |
| `hostname`, `service` | The stream fields: filter on them with `{hostname="websvcs", service="traefik"}`. `service` is the container name, or the unit name for host services (`haproxy`, `fail2ban`, `node_exporter`, `net_probe`, `snapraid-sync`) |
| `_msg`, `_time` | The message and the journal's timestamp |
| `priority` | syslog level, `0` emerg to `7` debug. Podman logs a container's stdout at `6` and its stderr at `3` whatever the line says, so for containers it tells the stream, not the severity; host services (`haproxy`, `fail2ban`) use it properly |
| `invocation_id` | One run of a unit: every line of one oneshot (`calliope`, `car_ingest`, `net_probe`, `image_updater`) |
| `code` | `func file:line` of the logging call; `write_journald src/ctr_logging.c:467` for every container line |
| `pid`, `boot_id` | From the journal; `errno` only when the journal set it |
| `RequestMethod`, `RequestHost`, `RequestPath`, `RequestScheme`, `RequestProtocol`, `DownstreamStatus`, `OriginStatus`, `Duration`, `OriginDuration`, `Overhead` (ns), `DownstreamContentSize`, `ClientHost`, `ClientAddr`, `RouterName`, `ServiceName`, `entryPointName`, `TLSVersion`, `TLSCipher`, `RetryAttempts`, `request_User-Agent`, `request_Referer`, `request_Remote-User` | Traefik access-log lines only, from the JSON access log; `RequestMethod:*` selects them. `_msg` is rewritten to `METHOD host/path status Nms client`. `request_Remote-User` is the Authelia user on authenticated requests |

Names with a hyphen need quotes: `"request_User-Agent":~"(?i)bot"`.

## Metrics

### Health at a glance

```promql
# Targets down, by node and job
up == 0

# Firing alerts, as vmalert records them
ALERTS{alertstate="firing"}

# Failed systemd units and restart loops
node_systemd_unit_state{state="failed"} == 1
increase(node_systemd_service_restart_total[1h]) > 0

# Uptime checks failing (Gatus); key is group_name
gatus_results_endpoint_success == 0
```

### Nodes

```promql
# Free disk, lowest first
sort(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|ramfs"} / node_filesystem_size_bytes)

# Memory available, CPU busy, load per core
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
1 - avg by (host) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
node_load15 / count by (host) (node_cpu_seconds_total{mode="idle"})

# Pressure stall: time waiting on IO
rate(node_pressure_io_waiting_seconds_total[5m])

# When each node was last deployed, and from which commit
(time() - homelab_deployed_timestamp_seconds) / 86400
homelab_deployed_info
```

### Media array and GPUs (websvcs)

```promql
smartctl_device_smart_status == 0
smartctl_device_temperature{temperature_type="current"}
smartctl_device_attribute{attribute_value_type="raw", attribute_name=~"Reallocated_Sector_Ct|Current_Pending_Sector|UDMA_CRC_Error_Count"}

# Disk I/O, the array's disks only (the VM's own are QEMU)
rate(node_disk_written_bytes_total[5m]) * on (host, device) group_left (model, serial) node_disk_info{host="websvcs", model!~"QEMU.*"}

# GPU load, memory and heat, websvcs' card and the desktops'
nvidia_smi_utilization_gpu_ratio
nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes
nvidia_smi_temperature_gpu
```

### Ingress and auth

```promql
# 5xx by service; top requested services
sum by (host, service) (rate(traefik_service_requests_total{code=~"5.."}[5m])) > 0
topk(10, sum by (service) (rate(traefik_service_requests_total[1h])))

# Mean latency by service
traefik_service_request_duration_seconds_sum / traefik_service_request_duration_seconds_count

# Cert days left, Traefik's and Gatus's views
(traefik_tls_certs_not_after - time()) / 86400
gatus_results_certificate_expiration_seconds / 86400

# Failed logins
sum(increase(authelia_authn{success="false"}[1h]))

# CrowdSec decisions by origin, what the appsec blocked, and what the VPS drops
sum by (origin) (cs_active_decisions)
sum(increase(cs_appsec_block_total[1h]))
sum by (origin) (rate(fw_bouncer_dropped_packets[5m]))

# VPS backends HAProxy can't reach; backend status
sum by (proxy) (rate(haproxy_backend_connection_errors_total[5m])) > 0
haproxy_backend_status == 0

# Tailnet: tailscaled complaints and headscale's node count
tailscaled_health_messages > 0
headscale_nodestore_nodes
```

### Jobs and freshness

```promql
# Days since the last good run (backups per exported_job, probes per probe)
(time() - homelab_backup_last_success_timestamp_seconds) / 86400
(time() - homelab_snapraid_last_success_timestamp_seconds) / 86400
(time() - homelab_net_probe_last_success_timestamp_seconds) / 3600
(time() - image_updater_last_success_timestamp_seconds) / 3600

# Image updater: images by result, days a pending update has been blocked
sum by (host, result) (image_updater_images)
image_updater_blocked_days > 0

# WAN and VPS path
homelab_speedtest_bits_per_second / homelab_isp_plan_bits_per_second
homelab_ping_rtt_seconds{path="vps"}
homelab_ping_loss_ratio
homelab_iperf_up == 0
```

### The pipeline itself

```promql
# Series and churn in VictoriaMetrics
vm_cache_entries{type="storage/hour_metric_ids"}
sum(rate(vm_new_timeseries_created_total[5m]))

# vmagent dropping or retrying writes
sum by (host) (increase(vmagent_remotewrite_packets_dropped_total[1h]))
sum by (host) (rate(vmagent_remotewrite_retries_count_total[5m]))

# fluent-bit shipping logs, per node
sum by (host) (rate(fluentbit_output_proc_bytes_total[5m]))

# Logs ingested per day, and VictoriaLogs' disk
sum(increase(vl_rows_ingested_total[24h]))
vl_data_size_bytes
```

### Finding names

- Metric names of a job: vmui's autocomplete, the MCP `metrics` tool with
  `match={job="JOB"}`, or `count by (__name__) ({job="JOB"})`
- Labels of one metric: the MCP `labels` tool with `match=METRIC`, or `group by (job, host) (METRIC)`
- Values of a label: the MCP `label_values` tool, or `count by (LABEL) (METRIC)`
- Something that stopped reporting: `last_over_time(METRIC[7d])` finds the last sample; a metric
  absent from a 30-day `metrics` listing never reached the store in that window
- Alerts and their expressions: the MCP `rules` and `alerts` tools, or vmalert's UI

MetricsQL extras worth knowing: `rate(m)` with no window picks a sane one; `last_over_time`,
`topk_last`, `default` and `keep_metric_names` are all there;
[MetricsQL](https://docs.victoriametrics.com/victoriametrics/metricsql/).

## Logs

LogsQL: filters first, then `|` pipes. Put the stream filter first (`{service="traefik"}`,
`{hostname="websvcs", service=~"calliope|car_ingest"}`): it narrows to the stream before any
scan, while `service:=traefik` works but scans. Always bound `_time` in vmui and curl; the MCP
tools take `start`/`end` instead, and an extra `_time:` just intersects with them. `AND` binds
tighter than `OR`, so parenthesise alternatives: `{service="x"} (i(error) OR i(fatal))`.

### Find

```logsql
# One service's last hour
_time:1h {service="calliope"}

# Errors on a node, any case
_time:1h {hostname="websvcs"} i(error)

# Warning or worse by syslog level (host services; containers' stderr is always 3)
_time:24h priority:<=4

# A phrase, and a regex in a field
_time:1h {service="traefik"} "connection refused"
_time:1h _msg:~"timeout|deadline"

# Every line of one run of a oneshot: list runs, then take an invocation_id
_time:1d {service="calliope"} | stats by (invocation_id) min(_time) start, count() lines | sort by (start desc)
_time:1d invocation_id:=ID
```

### Count and rank

```logsql
# Noisiest services today
_time:24h | stats by (hostname, service) count() lines | sort by (lines desc) | limit 20

# Error-ish lines per service, last hour
_time:1h i(error) | stats by (service) count() n | sort by (n desc)

# Errors over time, in 10-minute buckets
_time:6h {service="authelia"} i(error) | stats by (_time:10m) count() n
```

### Traefik access log

```logsql
# 5xx responses, newest first
_time:1h {service="traefik"} RequestMethod:* DownstreamStatus:>=500
  | fields _time, hostname, RequestHost, RequestPath, DownstreamStatus, RouterName

# Which routers are failing, and whether the origin or Traefik produced the status
_time:24h {service="traefik"} DownstreamStatus:>=500
  | stats by (RequestHost, RouterName, DownstreamStatus, OriginStatus) count() n | sort by (n desc)

# Requests by status per host
_time:1h {service="traefik"} RequestMethod:* | stats by (RequestHost, DownstreamStatus) count() n

# Slow requests (> 2 s; Duration is nanoseconds), and latency percentiles per router
_time:1h {service="traefik"} Duration:>2000000000 | fields _time, RequestHost, RequestPath, Duration
_time:24h {service="traefik"} RequestMethod:* | stats by (RouterName) quantile(0.5, Duration) p50, quantile(0.99, Duration) p99, count() n | sort by (p99 desc)

# Top client IPs, and what one of them asked for
_time:24h {service="traefik"} RequestMethod:* | stats by (ClientHost) count() n | sort by (n desc) | limit 10
_time:24h {service="traefik"} ClientHost:=IP | fields _time, RequestHost, RequestPath, DownstreamStatus

# Who used which service (Authelia user forwarded by Traefik), and crawlers
_time:24h {service="traefik"} "request_Remote-User":* | stats by ("request_Remote-User", RequestHost) count() n | sort by (n desc)
_time:24h {service="traefik"} "request_User-Agent":~"(?i)bot|crawl|spider" | stats by ("request_User-Agent") count() n | sort by (n desc)
```

### Auth and security

```logsql
# Authelia logs logfmt: unpack it, then filter and group on its fields
_time:24h {service="authelia"} | unpack_logfmt | filter level:=error | stats by (msg, remote_ip) count() n | sort by (n desc)
_time:24h {service="authelia"} "Unsuccessful" | unpack_logfmt | fields _time, msg, remote_ip

# CrowdSec bans: pull scenario, IP and country out of the message
_time:24h {service="crowdsec"} "ban on Ip"
  | extract 'msg="(<source>) <scenario> by ip <ip> (<country>/<asn>) : <duration> ban'
  | stats by (scenario, country) count() n | sort by (n desc)

# fail2ban on the VPS (host service; "Restore Ban" lines are re-applied old bans)
_time:7d {service="fail2ban"} "] Ban " | extract "[<jail>] Ban <ip>" | stats by (jail) count() bans, count_uniq(ip) ips

# HAProxy on the VPS logs TCP connections with the SNI it routed on
_time:24h {service="haproxy"} | extract "sni=<sni>" | stats by (sni) count() n | sort by (n desc)
```

### Finding fields

- Fields in a result: `_time:1h {service="SERVICE"} | field_names`, or the MCP `field_names` tool
- Values of a field: `_time:1h {service="traefik"} | field_values RouterName`, or `field_values`
- Which services log on a node: the MCP `stream_field_values` tool with `field=service` and
  `query={hostname="NODE"}`, or `| stats by (hostname, service) count()`
- Top values of every field at once: the MCP `facets` tool; counts over time: `hits`
- Reference: [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/)
