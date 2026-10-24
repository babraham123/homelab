# 05. Network speed dashboard and alerts

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-23
Blocked by: 03, 04

## Problem

03 and 04 produce pings hourly, speed tests every six hours and the VPS's throughput daily;
they need a place to read them and a threshold that says when they matter.

## Change

1. **Alerts**, `src/services/vmalert/configs/network.yml`:
   - `WanSlow`: download under half of `isp.down_mbps`, or upload under half of
     `up_mbps`, for 13h (three runs), warning. Rendered from `vars.yml`, so the file is a `.j2`.
   - `NetProbeStale`: no speed test success in 25h or VPS iperf3 success in 49h, warning
     (secsvcs is always on)
   - `VpsPathDown`: `homelab_ping_loss_ratio{path="vps"} == 1` for 3h (three hourly pings),
     warning. The pve2 path never alerts: pve2 is off most of the time.
2. **Dashboard** `src/services/grafana/dashboards/network.json`: WAN download and upload against
   the plan speed, latency, jitter and loss; iperf3 per path and direction, with retransmits;
   ping RTT and loss per path; pfSense's gateway RTT and loss beside them, from the existing
   Telegraf data; skips per probe and reason, so a network that is always busy at 21:00
   shows.
3. **Docs**: `docs/services.md` alert list.

## Acceptance

- The dashboard shows a week of runs.
- Setting `down_mbps` far above the real speed fires `WanSlow` after three runs.

## Comments
