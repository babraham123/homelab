# 11. Keep vmagent's remote-write buffer on its volume, and cap it

Status: ready-for-agent
Type: task
Repo: homelab
Source: found in observability/04 (2026-09-27)

## Problem

`src/victoriametrics/vmagent.container.j2.j2` mounts `vmagentdata.volume` at
`/vmagentdata`, but never sets `-remoteWrite.tmpDataPath`. vmagent's default is the
relative path `vmagent-remotewrite-data`, so the on-disk queue is written to the
container's own writable layer. Nothing uses the volume.

Quadlet containers run with `--rm`. Every restart, reboot or `AutoUpdate=registry` image
update discards the container, and with it any samples still queued for
`metrics.SITE`. The loss is worst exactly when it matters: after a secsvcs or network
outage, the backlog is dropped if homesvcs/websvcs restart before it drains.

`-remoteWrite.maxDiskUsagePerURL` is also unset, which means unlimited. A long secsvcs
outage grows the queue until the VM's disk fills.

Memory isn't the issue. vmagent keeps only a small in-memory block per queue and spills
the rest to the file queue, so an outage costs disk, not RAM.

## Change

In the shared template, for every node that runs vmagent (homesvcs, websvcs, and the VPS
in observability/08):

```
     --remoteWrite.tmpDataPath="/vmagentdata" \
     --remoteWrite.maxDiskUsagePerURL="1GiB" \
```

About 1 GiB:
- **Scale:** 10 s scrapes of a few thousand series are on the order of tens of MB per
  day of outage, so 1 GiB is weeks. The number is an estimate; confirm it with
  `vmagent_remotewrite_pending_data_bytes` during the acceptance test and adjust.
- **Past the cap:** vmagent drops the oldest data, and the existing
  `PersistentQueueIsDroppingData` rule in `src/vmalert/configs/vmagent.yml` fires.

Update observability/04's Answer (follow-up step 2) and observability/08 to point here,
since this fix no longer rides with 08.

## Acceptance

- The rendered quadlet on homesvcs and websvcs carries both flags.
- Stop VictoriaMetrics on secsvcs for 10 minutes. Restart `vmagent` on websvcs during
  the outage, then start VictoriaMetrics again. The websvcs series have no gap.
- `du -sh` on the `systemd-vmagentdata` volume shows the queue grew, then drained.

## Comments
