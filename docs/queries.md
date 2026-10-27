# Metrics and log queries

Starting points for querying VictoriaMetrics (PromQL/MetricsQL) and VictoriaLogs (LogsQL), from the
vmui pages, curl ([debugging](debugging.md#observability)), Grafana's Explore, or Claude Code's MCP
servers ([guide](guides/claude_telemetry.md)). The alert rules in `src/services/vmalert/configs/`
and the dashboards in `src/services/grafana/dashboards/` hold the full set.

## Labels and fields

- `host`: the bare node name (`secsvcs`, `websvcs`, `pve2`) on every scraped series, the same value
  as `hostname` on every log line, so one value filters both
- `job`: the scrape job, per node in `src/nodes/<node>/prometheus.yml.j2`

| Node | Jobs |
| ---- | ---- |
| secsvcs | `authelia`, `vmalert`, `victoriametrics`, `victorialogs`, `fluentbit`, `gatus`, `crowdsec`, `crowdsec_appsec`, `ntfy`, `traefik`, `node_exporter`, `node_exporter_pve` (pve1) |
| websvcs | `vmagent`, `fluentbit`, `crowdsec_appsec`, `finance_exporter`, `traefik`, `node_exporter`, `node_exporter_pve` (pve2), `smartctl`, `nvidia_gpu`, `nvidia_gpu_desktops` |
| homesvcs | `vmagent`, `fluentbit`, `crowdsec_appsec`, `traefik`, `node_exporter` |
| vpnsvcs | `vmagent`, `fluentbit`, `haproxy`, `crowdsec_firewall_bouncer`, `headscale`, `tailscaled`, `node_exporter` |

Log fields, set by `src/services/fluentbit/journald.lua.j2`:

| Field | What |
| ----- | ---- |
| `hostname`, `service` | Stream fields; `service` is the container name, or the unit name for host services |
| `_msg`, `_time` | The message and the journal's timestamp |
| `priority` | syslog level as a string, `0` emerg to `7` debug; containers log most lines at `6` |
| `invocation_id` | One run of a unit: every line of one oneshot (calliope, car_ingest) |
| `code`, `pid`, `boot_id`, `errno` | From the journal |
| `RequestHost`, `RequestPath`, `DownstreamStatus`, `Duration` (ns), `ClientHost`, `RouterName`, `request_User-Agent`, ... | Traefik access log lines only, which also have `RequestMethod` |

- Only the units in each node's `homelab_services` reach VictoriaLogs; the rest of the journal stays
  on the node

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

# Uptime checks failing (Gatus)
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
```

### Media array (websvcs)

```promql
smartctl_device_smart_status == 0
smartctl_device_temperature{temperature_type="current"}
smartctl_device_attribute{attribute_value_type="raw", attribute_name=~"Reallocated_Sector_Ct|Current_Pending_Sector|UDMA_CRC_Error_Count"}

# Disk I/O, the array's disks only (the VM's own are QEMU)
rate(node_disk_written_bytes_total[5m]) * on (host, device) group_left (model, serial) node_disk_info{host="websvcs", model!~"QEMU.*"}
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

# CrowdSec decisions and what the VPS drops
sum by (origin) (cs_active_decisions)
sum by (origin) (rate(fw_bouncer_dropped_packets[5m]))

# VPS backends HAProxy can't reach
sum by (proxy) (rate(haproxy_backend_connection_errors_total[5m])) > 0
```

### Jobs and freshness

```promql
# Days since the last good run
(time() - homelab_backup_last_success_timestamp_seconds) / 86400
(time() - homelab_snapraid_last_success_timestamp_seconds) / 86400
(time() - image_updater_last_success_timestamp_seconds) / 3600

# WAN and VPS path
homelab_speedtest_bits_per_second / homelab_isp_plan_bits_per_second
homelab_ping_rtt_seconds{path="vps"}
homelab_ping_loss_ratio
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

# Logs ingested per day
sum(increase(vl_rows_ingested_total[24h]))
```

- Find a metric name: vmui's autocomplete, or `count by (__name__) ({job="JOB"})`
- Labels of one metric: `group by (job, host) (METRIC)`

## Logs

LogsQL: filters first (words, `field:=value`, `_time:`), then `|` pipes. Always bound `_time`.

### Find

```logsql
# One service's last hour
_time:1h service:=calliope

# Errors on a node, any case
_time:1h hostname:=websvcs i(error)

# Warning or worse (priority 0-4)
_time:24h priority:~"^[0-4]$"

# A phrase, and a word anywhere in a field
_time:1h service:=traefik "connection refused"
_time:1h _msg:~"timeout|deadline"

# Every line of one run of a oneshot: take invocation_id from any line of it
_time:1d service:=calliope | stats by (invocation_id) min(_time) start, count() lines
_time:1d invocation_id:=ID
```

### Count and rank

```logsql
# Noisiest services today
_time:24h | stats by (hostname, service) count() lines | sort by (lines desc) | limit 20

# Error-ish lines per service, last hour
_time:1h i(error) | stats by (service) count() n | sort by (n desc)

# Errors over time, in 10-minute buckets
_time:6h service:=authelia i(error) | stats by (_time:10m) count() n
```

### Traefik access log

```logsql
# 5xx responses, newest first
_time:1h service:=traefik RequestMethod:* DownstreamStatus:>=500
  | fields _time, hostname, RequestHost, RequestPath, DownstreamStatus, RouterName

# Requests by status per host
_time:1h service:=traefik RequestMethod:* | stats by (RequestHost, DownstreamStatus) count() n

# Slow requests (> 2 s; Duration is nanoseconds)
_time:1h service:=traefik RequestMethod:* Duration:>2000000000
  | fields _time, RequestHost, RequestPath, Duration

# Top client IPs, and what one of them asked for
_time:24h service:=traefik RequestMethod:* | stats by (ClientHost) count() n | sort by (n desc) | limit 10
_time:24h service:=traefik ClientHost:=IP | fields _time, RequestHost, RequestPath, DownstreamStatus
```

### Auth and security

```logsql
# Authelia's failed logins and bans
_time:24h service:=authelia i("unsuccessful") OR i("banned")

# CrowdSec's bans ("performed ... : 4h ban on Ip ...")
_time:24h service:=crowdsec i(ban)
```

- Field names in a result: `_time:1h service:=SERVICE | field_names`
- Values of a field: `_time:1h service:=traefik | field_values RouterName`
- Reference: [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/),
  [MetricsQL](https://docs.victoriametrics.com/victoriametrics/metricsql/)
