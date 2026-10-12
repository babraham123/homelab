# Maintenance

## Restart a service
- Determine which VM it's running on and restart
```bash
ssh manualadmin@secsvcs
sudo systemctl restart SERVICE
```

## Upgrade all systems
Once a year

- WiFi AP firmware
  - Download the firmware bin, [TP-Link
    EAP660](https://support.omadanetworks.com/en/download/firmware/eap660-hd/v1/)
  - Go to AP's admin console (https://wifi.SITE_URL) >> System >> Firmware Update
  - Make sure to apply every incremental update

TODO: router, all VMs, pinned docker images

## Add a new user
TODO: code edits, lldap for new user

## Update secrets
```bash
ssh manualadmin@pve1
sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs
```

## Refresh certificates
You should receive email notifications several weeks in advance of certificate expiration.

- Once every 2 months
```bash
ssh manualadmin@pve1
# Copy over the ACME generated certs 
sudo /root/homelab-rendered/src/nodes/pve1/certificates/acme_transfer.sh
```

- Once a year
```bash
ssh manualadmin@pve1
# Generate self signed certs
sudo /root/homelab-rendered/src/nodes/pve1/certificates/self_signed_cert_gen.sh
# Generate SSH certs
sudo /root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen.sh
# Generate SSH certs for the Gaming VM
ssh autoadmin@router start_pve2
ssh autoadmin@pve2 start_gaming_vm
sudo /root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen_windows.sh
```

## Backups
- Runs itself every Saturday 02:00 from pve1; the ntfy `alert` topic gets a summary and
  `BackupStale` fires after 8 quiet days. Run it by hand with
  `sudo systemctl start backup_orchestrator` on pve1 (blocks for the run;
  `journalctl -u backup_orchestrator -f`).
- Once a year: the [restore test](guides/restore.md#annual-restore-test). Last done: never.
- Media array on pve2: `snapraid status` on websvcs; a failed disk follows [pve2
  storage](guides/pve2_storage.md#day-to-day).

## Container images
`image_updater.timer` updates every image on vpnsvcs (20:00), homesvcs (20:30), websvcs (21:00)
and secsvcs (21:30) each night, behind a Trivy scan: a fixable HIGH or CRITICAL CVE blocks the new
image, and the old one keeps running. Design: [ADR 0008](adr/0008-scanned-image-updater.md).

| ntfy `alert` topic | Priority |
|---|---|
| Update blocked by the scan, daily | 3; 5 after 7 days, with the `accept` command |
| Update failed, rolled back to the previous image | 4 |
| Updater broken, or the Trivy DB refresh failed | 5 |

`ImageUpdaterStale` fires after 36 h without a clean run.

```bash
ssh manualadmin@NODE
sudo journalctl -u image_updater
# What would change, with scan results; loads and restarts nothing
sudo /root/homelab-rendered/src/base/podman/image_updater.sh --dry-run
# A run now
sudo systemctl start image_updater
```

- Override a blocked image, after reading its findings. Either:
  - every digest until a date: add the CVE to `src/services/<service>/.trivyignore` with the
    reason, then deploy
    ```text
    # Not reachable: the vulnerable parser only reads files from the image itself
    CVE-2026-12345 exp:2026-12-31
    ```
  - that digest only: on the node, as manualadmin (never through the dispatcher or OliveTin),
    `sudo /root/homelab-rendered/src/base/podman/image_updater.sh accept CONTAINER`. It rescans,
    prints the findings, records the digest and notifies; the next run loads it.
- Built images: a service with a `src/services/<service>/build.sh` (`versions`, `build TAG`) is
  rebuilt when its release versions change. One without, like `geoip_generator`, is rebuilt by
  installing it again.
- Roll back by hand: `podman tag localhost/NAME:rollback localhost/NAME:TAG`, then
  `systemctl restart CONTAINER`. The updater doesn't retry that digest; it moves on when upstream
  does.

## Alerting pipeline test
Once a year, with the backup restore test. Last done: never. Every alert goes vmalert → Alertmanager
→ ntfy-alertmanager → ntfy → phone, plus two emails (`+alert@` from Alertmanager, `+alert2@` from
ntfy-alertmanager); the VPS's `deadman` timer watches that path from outside and reports to
`+alert@` and a private ntfy.sh topic.

| # | Test | How | Expect |
|---|---|---|---|
| 1 | Full path from vmalert | With the phone on mobile data: on secsvcs, `/etc/opt/vmalert/pipeline_test.yml` with `alert: PipelineTest, expr: vector(1), labels: {severity: critical, host: secsvcs}`; `systemctl restart vmalert`. Then delete it and restart vmalert again (`install_vmalert` also clears it) | ntfy priority 5, `rotating_light`, `secsvcs` tag within `group_wait` (30 s) plus one evaluation; email to `+alert@` and `+alert2@`. After the delete: ntfy `resolved,tada` priority 1 and a resolved email |
| 2 | Dead-man switch | `systemctl stop alertmanager` on secsvcs, then `systemctl start alertmanager` | `deadman`: email + ntfy.sh push within 15 min; a recovery notice after the start |

## Disaster recovery
- Restore a file, a VM or a host: [restore guide](guides/restore.md)
- pve1's SSD died, or its AGE key, private CA, SSH CA or `vars.yml` is gone: [pve1 disaster
  recovery](guides/pve1_recovery.md)
