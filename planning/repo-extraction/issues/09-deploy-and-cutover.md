# 09. Deploy and cut over each node

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-25
Blocked by: 08

## Problem

After the deploy, the image updater's timer and every `install_svcs.sh` call
`/usr/local/bin/image_updater`, which isn't on the nodes until its install case runs. The other
pieces need their install cases or a rebuild, and a few leftovers stay behind.

## Change

1. `tools/deploy_src.sh`, then right away, before the next nightly run or any service install:
   `ssh autoadmin@<node> install_image_updater` on secsvcs, homesvcs, websvcs and vpnsvcs.
2. **net_probe, secsvcs:** optionally delete `/var/lib/net_probe/state.json` first, to skip the
   gap in the dashboards while each test reruns (up to 6 h for the speed test and pve2, 24 h for
   the VPS). Then `ssh autoadmin@secsvcs install_net_probe`.
3. **car_ingest, websvcs:** if `/etc/systemd/system/car_ingest.service` exists (an install of the
   old host version), remove it and `systemctl daemon-reload`, or it shadows the unit the quadlet
   generates. Then `ssh autoadmin@websvcs install_car_ingest`; it builds the image, the first real
   build of car-ingest's Containerfile.
4. **Rebuilt images:** calliope, yt_to_audiobook and bookmark_handoff (websvcs) and
   geoip_generator (vpnsvcs) are first built from their new sources by the nightly update, or now
   with `install_<service>` on their node. Check each build passes the scan gate.
5. **websvcs leftovers:** delete `/etc/opt/calliope/calliope_batch.py` and
   `/etc/opt/yt_to_audiobook/`. `/etc/opt/calliope/voices` is still used.

## Acceptance

- `image_updater --dry-run` on each node lists its images and loads nothing.
- `systemctl start net_probe` on secsvcs writes `homelab_net_probe.prom`; the network dashboard
  fills in at each test's next slot.
- `systemctl start car_ingest` imports a test upload; the Car dashboard shows it.
- One run each of calliope, yt_to_audiobook, bookmark_handoff and geoip_generator succeeds from
  the new images.
