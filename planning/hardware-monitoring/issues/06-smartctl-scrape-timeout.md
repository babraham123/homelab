# 06. smartctl_exporter on websvcs never answers a scrape

Status: needs-triage
Type: task
Repo: homelab
Source: queries.md verification 2026-10-27

## Problem

`up{job="smartctl"}` has been 0 for the whole 30-day window and no `smartctl_*` series exists in
the store, so `hardware.yml`'s `DiskSmartFailed` and reallocated-sector alerts can never fire and
`disks.json` is empty. vmagent on websvcs logs every scrape as:

```text
cannot scrape target "http://host.containers.internal:9633/metrics" ({job="smartctl"}):
context deadline exceeded
```

The exporter itself is running: its journal (service `smartctl_exporter`, 2026-10-26 19:53) shows
v0.15.0 starting, listening on `:9633` with the four `ata-WDC_WD80EAAZ` devices filtered in. So the
port answers slowly, not never. The likely cause is the array spinning down (`hd-idle`,
f4d2a210): each scrape makes the exporter run `smartctl` against four standby disks, which either
waits for them to spin up or blocks, and the scrape timeout passes first. That also defeats the
spin-down.

## Change

- Confirm on websvcs: `time curl -s localhost:9633/metrics | head`, and `hdparm -C` on the disks
  before and after.
- Run the exporter so a scrape never waits on a disk: `--smartctl.powermode-check=standby` (skip
  disks in standby, report `smartctl_device_power_state` instead) and a `--smartctl.interval`
  longer than the scrape interval so results come from its cache. Both go in
  `src/services/snapraid/smartctl_exporter.service`.
- If a cold scrape still takes seconds, raise `scrape_timeout` for the `smartctl` job in
  `src/nodes/websvcs/prometheus.yml.j2`.

## Acceptance

- `up{job="smartctl"} == 1` and `smartctl_device_smart_status` has one series per array disk.
- `hdparm -C` shows the disks staying in standby across several scrapes.
- Issue 02's dashboard and alerts have data.
