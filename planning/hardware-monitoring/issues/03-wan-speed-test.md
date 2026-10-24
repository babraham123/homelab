# 03. Scheduled WAN speed test from secsvcs

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-23

## Problem

pfSense reports how much traffic crosses the WAN, not how much it could carry. A slow ISP day,
a degraded modem link or pfSense becoming the bottleneck all look like a quiet network.

## Change

1. **`net_probe`**, a debian service on secsvcs, the probe host for 03 and 04:
   - `src/base/net_probe/net_probe.py.j2`, stdlib only
   - `net_probe.service` (oneshot, "Homelab:" description, `TimeoutStartSec=10min`) and
     `net_probe.timer`: `OnCalendar=*:05`, `Persistent=true`, no random delay, so slots land
     on their hour
   - `install_svcs.sh net_probe` case; add `net_probe` to secsvcs's `debian_services`
2. **Coordination**, in the runner, so 04's probes only declare themselves:
   - **No overlap.** One unit, one timer: systemd doesn't start a oneshot that is still running,
     and a manual `systemctl start net_probe` waits in the same queue. Within a run, probes go
     one at a time, light before heavy: pings, then the speed test, the pve2 iperf3, the VPS
     iperf3. The pings see the idle path, and no test competes with another.
   - **Slots.** Each heavy probe declares its slot hours in the template (speed test: 03, 09, 15,
     21). It is due when its latest slot is after its last success. A due probe that is skipped
     stays due and retries on the next hourly run, until it succeeds or its next slot arrives,
     so it runs at most once per slot. Runs missed while secsvcs was down collapse into one at
     boot (`Persistent=true`).
   - **Busy check.** Before a heavy probe, one instant query to VictoriaMetrics
     (`metrics.SITE:8428`, the `VM_ADMIN_PASSWORD` secret via `get_secret.sh`), declared per
     probe with a threshold. The speed test's: pfSense's WAN traffic over the last 5 minutes
     (`net_bytes_recv` plus `net_bytes_sent` from Telegraf, on the interface the pfSense
     dashboard's `$WAN` picks) above 30% of the plan speed. If the query fails, the probe runs
     anyway: a metrics outage shouldn't stop the measurements.
   - **Never fails the unit.** A skip or error is a metric, not a failed unit:
     `homelab_net_probe_skipped_total{probe, reason}` (`busy`, `unreachable`, `server_busy`,
     `error`), `homelab_net_probe_last_attempt_timestamp_seconds{probe}`,
     `homelab_net_probe_last_success_timestamp_seconds{probe}`.
   - **State.** Last attempt, last success, last results and skip counts in
     `/var/lib/net_probe/state.json`. Every run rewrites `homelab_net_probe.prom` from it,
     atomically (the `write_prom` pattern from `snapraid_run.sh.j2`), so a probe not due this
     hour keeps its last values.
3. **Speed test:** Ookla's CLI, the `linux-x86_64` tarball pinned by version and sha256 in the
   install case. `speedtest --format=json --accept-license --accept-gdpr`. Metrics:
   - `homelab_speedtest_download_bits_per_second`, `..._upload_bits_per_second`
   - `homelab_speedtest_latency_seconds`, `..._jitter_seconds`, `..._packet_loss_ratio`
   - `homelab_speedtest_info{server, isp}` 1
   - No `--server-id`: Ookla picks the nearest server each run. A pinned server going away
     would break the probe, and the plan speed is what the result is judged against
4. **Plan speed** in `vars.yml` (and the template), a top-level `isp:` with `down_mbps` and
   `up_mbps`, for the busy check and 05's alerts. The template's values are placeholders.

## Acceptance

- `systemctl start net_probe` on secsvcs writes the speed test metrics; they appear under
  `host="secsvcs"`.
- The timer fires hourly; the speed test runs at its four slots.
- With a large download running at a slot, the speed test records `reason="busy"` and runs on
  the next hourly run instead.
- Two `systemctl start net_probe` in a row never run two tests at once.

## Comments
