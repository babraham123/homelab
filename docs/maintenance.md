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
  - Download the firmware bin, [TP-Link EAP660](https://support.omadanetworks.com/en/download/firmware/eap660-hd/v1/)
  - Go to AP's admin console (https://wifi.SITE_URL) >> System >> Firmware Update
  - Make sure to apply every incremental update

TODO: router, all VMs, pinned docker images 

## Add a new user
TODO: code edits, lldap for new user

## Update secrets
```bash
ssh manualadmin@pve1
sudo /root/homelab-rendered/src/pve1/secret_update.sh secsvcs
```

## Refresh certificates
You should receive email notifications several weeks in advance of certificate expiration.

- Once every 2 months
```bash
ssh manualadmin@pve1
# Copy over the ACME generated certs 
sudo /root/homelab-rendered/src/certificates/acme_transfer.sh
```

- Once a year
```bash
ssh manualadmin@pve1
# Generate self signed certs
sudo /root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
# Generate SSH certs
sudo /root/homelab-rendered/src/certificates/ssh_cert_gen.sh
# Generate SSH certs for the Gaming VM
ssh autoadmin@router start_pve2
ssh autoadmin@pve2 start_gaming_vm
sudo /root/homelab-rendered/src/certificates/ssh_cert_gen_windows.sh
```

## Backups
- Runs itself every Saturday 02:00 from pve1; the ntfy `alert` topic gets a summary and `BackupStale` fires after 8 quiet days. Run it by hand with `sudo systemctl start backup_orchestrator` on pve1 (blocks for the run; `journalctl -u backup_orchestrator -f`).
- Once a quarter: the [restore test](guides/restore.md#quarterly-restore-test). Last done: never.
- Media array on pve2: `snapraid status` on websvcs; a failed disk follows [pve2 storage](guides/pve2_storage.md#day-to-day).

## Alerting pipeline test
Once a quarter, with the backup restore test. Last done: never. Every alert goes
vmalert → Alertmanager → ntfy-alertmanager → ntfy → phone, plus two emails
(`+alert@` from Alertmanager, `+alert2@` from ntfy-alertmanager); the VPS's `deadman`
timer watches that path from outside and reports to `+alert@` and a private ntfy.sh
topic. `AM='https://alert.SITE'`, with the Alertmanager admin password
(`sops -d /root/secrets/secsvcs.yaml | yq .alertmanager_admin_password` on pve1).

| # | Test | How | Expect |
|---|---|---|---|
| 1 | Alertmanager → ntfy | `amtool alert add PipelineTest severity=warning host=secsvcs.SITE --alertmanager.url=$AM` (`podman exec alertmanager amtool ...` on secsvcs, or `curl -u admin: -XPOST $AM/api/v2/alerts -d '[{"labels":{"alertname":"PipelineTest","severity":"warning"}}]'`) | ntfy priority 3, tag `warning`, `secsvcs` tag; email to `+alert@` and `+alert2@` |
| 2 | Full path from vmalert | On secsvcs, `/etc/opt/vmalert/pipeline_test.yml` with `alert: PipelineTest, expr: vector(1), labels: {severity: critical}`; `systemctl restart vmalert` | ntfy priority 5, `rotating_light`, within `group_wait` (30 s) plus one evaluation |
| 3 | Severity map | repeat 1 with `severity=error`, then `info` | priorities 4 and 1 |
| 4 | Inhibition | fire `critical` and `warning` with the same `alertname` and `instance` | only the critical one is delivered |
| 5 | Resolve | delete `pipeline_test.yml`, restart vmalert; let the amtool alerts expire (`--end=now`) | ntfy `resolved,tada` priority 1; resolved email |
| 6 | Silence button | tap the ntfy action | Alertmanager shows a 24 h silence; no repeat |
| 7 | Phone off-LAN | repeat 1 with the phone on mobile data | notification arrives |
| 8 | ntfy down | `systemctl stop ntfy` on secsvcs, repeat 1 | both emails still arrive; `podman logs ntfy-alertmanager` shows the failure; `deadman` fires after 15 min |
| 9 | ntfy-alertmanager down | stop it, repeat 1 | `+alert@` email still arrives |
| 10 | Alertmanager down | `systemctl stop alertmanager` | `deadman`: email + ntfy.sh push within 15 min; recovery notice after `systemctl start alertmanager` |
| 11 | secsvcs down | shut down the secsvcs VM | `deadman` fires the same way |

Remove `pipeline_test.yml` afterwards (`install_vmalert` also clears it).

## Disaster recovery
- Restore a file, a VM or a host: [restore guide](guides/restore.md)
- pve1's SSD died, or its AGE key, private CA, SSH CA or `vars.yml` is gone: [pve1 disaster recovery](guides/pve1_recovery.md)
