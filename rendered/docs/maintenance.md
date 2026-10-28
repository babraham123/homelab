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

- Fresh backups first: `sudo systemctl start backup_orchestrator` on pve1
- pfSense: snapshot the router VM in PVE, then the [router guide](guides/router.md#updates)
- Debian nodes: unattended-upgrades only applies security updates, so pull everything else. Go in
  dependency order, secsvcs last since every other node authenticates and logs through it:
  vpnsvcs, homesvcs, devtop, websvcs (`ssh autoadmin@router start_pve2` first), secsvcs

```bash
ssh autoadmin@NODE upgrade
# Only if upgrade ended with "reboot required"
ssh autoadmin@NODE reboot
# Every homelab unit is back
ssh autoadmin@NODE failed_units
```

- Headscale is a GitHub release, not an apt package, pinned by version and sha256 in the
  `headscale` case of `src/nodes/vpnsvcs/install_svcs.sh.j2` (the sha256 is the deb's line in
  the release's `checksums.txt`): set both, deploy, then `sudo
  /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh headscale`
- mdns-repeater is pinned the same way, by commit, in the `mdns_repeater` case of
  `src/base/debian/install_svcs.sh`
- net_probe and Ookla's speedtest CLI are pinned by URL and sha256 in the `net_probe` case of
  `src/base/debian/install_svcs.sh`: set both to the new release or version, deploy, then
  `ssh autoadmin@secsvcs install_net_probe`
- PVE and PBS point releases: pve2 (PBS is local) then pve1, per the [Proxmox
  guide](guides/proxmox.md#minor-version), which also has the major-version path
- Container images update themselves nightly; see [Container images](#container-images)

## Add a new user

- In `vars.yml`, append the username to `users`: the Headscale ACL puts them in `group:family` and
  lets them reach their own devices. Anyone outside the family stays out of `users` and gets
  `tailscale_extra_acls` rules instead. Deploy, then reload the ACL:

```bash
tools/deploy_src.sh
ssh manualadmin@vpnsvcs
sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh headscale
```

- In LLDAP (https://ldap.SITE_URL), create the user with the same username, so Headscale's
  `user@` matches, and add them to groups:

| Group | Grants |
| --- | --- |
| `authelia_gen_access` | Every Authelia-protected subdomain; Readeck user |
| `ntfy_access` | An ntfy account, from a welcome email; leaving deletes it. Never empty it: that deletes everyone's |
| `headscale_access` | VPN sign-in |
| `command_general` | OliveTin's general commands |
| `telemetry_access` | VictoriaMetrics, VictoriaLogs and Alertmanager UIs |
| `grafana_admin`, `hass_admin`, `command_admin`, `readeck_admin`, `storyteller_admin` | Admin in that app; admins only |

- Their first sign-in, at https://auth.SITE_URL: register a TOTP app or a security key. Away from
  home and the VPN every subdomain requires it.
- Apps that create their account at first sign-in, so have the user sign in to each once:
  - Grafana: Viewer, or Admin with `grafana_admin`
  - Home Assistant: a person is created; admin with `hass_admin`
  - Headscale: `tailscale up --login-server https://vpn.SITE_URL:443 --accept-routes`
  - Storyteller: permissions are set at first sign-in, so set the groups before it
  - Vaultwarden: sets their master password; only then can an organization owner add them
- ntfy: within 15 minutes of joining `ntfy_access` they get a welcome email with their ntfy
  login. To enroll their phone for mobile push, they open https://idp-push.SITE_URL/enroll after
  signing in with TOTP or a security key

## Update secrets

```bash
ssh manualadmin@pve1
sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh secsvcs
```

## Refresh certificates

You should receive email notifications several weeks in advance of certificate expiration.

- ACME certs: the weekly backup run installs them; cert_notifier emails after 3 weeks without.
  By hand:

```bash
ssh manualadmin@pve1
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
  `BackupStale` fires after 15 quiet days, so one week can be skipped.
- OliveTin's pve1 buttons: **Backup Now** starts a run (`journalctl -u backup_orchestrator -f` on
  pve1); **Skip Next Backup** makes the next scheduled run do nothing. Undo a skip with
  `sudo rm /var/lib/backup_orchestrator/skip_next` on pve1.
- Once a year: the [restore test](guides/restore.md#annual-restore-test). Last done: never.
- Media array on pve2: `snapraid status` on websvcs; a failed disk follows [pve2
  storage](guides/pve2_storage.md#day-to-day).

## Container images

`image_updater.timer` updates every image on vpnsvcs (20:00), homesvcs (20:30), websvcs (21:00)
and secsvcs (21:30) each night (each node's `image_updater_slot`), behind a Trivy scan: a fixable
HIGH or CRITICAL CVE blocks the new image, and the old one keeps running. Design: [ADR
0008](adr/0008-scanned-image-updater.md); the script:
[podman-image-updater](https://github.com/babraham123/podman-image-updater).

| ntfy `alert` topic | Priority |
| --- | --- |
| Update blocked by the scan, daily | 3; 5 after 7 days, with the `accept` command |
| Update failed, rolled back to the previous image | 4 |
| Updater broken, a registry still failing after two retries, or the Trivy DB refresh failed | 5 |

`ImageUpdaterStale` fires after 36 h without a clean run. `ssh autoadmin@NODE update_images` runs
the same gated update now, after a `.trivyignore` change or a pinned-image bump.

```bash
ssh manualadmin@NODE
sudo journalctl -u image_updater
# What would change, with scan results; loads and restarts nothing
sudo image_updater --dry-run
# A run now
sudo systemctl start image_updater
```

- Override a blocked image, after reading its findings. Either:
  - every digest until a date: add the CVE to `.trivyignore` in the service's dir (its first
    `dirs` entry in the inventory, default `src/services/<service>/`) with the reason, then
    deploy

    ```text
    # Not reachable: the vulnerable parser only reads files from the image itself
    CVE-2026-12345 exp:2026-12-31
    ```

  - that digest only: on the node as root (never through the dispatcher or OliveTin),
    `sudo image_updater accept CONTAINER`. It rescans, prints the findings, records the digest and
    notifies; the next run loads it. For a built image it builds and scans instead, and records the
    `build.sh` inputs, so the next run's build of the same inputs passes.
- Built images: every one has a `build.sh` (`versions`, `build TAG`) in its service's dir, and
  is rebuilt through the scan gate when any input it reports changes, like `geoip_generator`'s
  haproxy-mapper commit and base image digests. The render fails for a `build:` image without one.
- Roll back by hand: `podman tag localhost/NAME:rollback localhost/NAME:TAG`, then
  `systemctl restart CONTAINER`. The updater doesn't retry that digest; it moves on when upstream
  does.
- Update the updater itself: set `tag` and `sha` (the sha256 in that release's notes, or its
  `image_updater.sha256` asset) in the `image_updater` case of `src/base/debian/install_svcs.sh`,
  deploy, then run `install_image_updater` on each node. A deploy alone only changes its image
  list.

## Alerting pipeline test

Once a year, with the backup restore test. Last done: never. Every alert goes vmalert → Alertmanager
→ ntfy-alertmanager → ntfy → phone, plus an email to `+alert@` from Alertmanager; the VPS's
`deadman` timer watches that path from outside and reports to `+alert@` and a private ntfy.sh
topic.

| # | Test | How | Expect |
| --- | --- | --- | --- |
| 1 | Full path from vmalert | With the phone on mobile data: on secsvcs, `/etc/opt/vmalert/pipeline_test.yml` with `alert: PipelineTest, expr: vector(1), labels: {severity: critical, host: secsvcs}`; `systemctl restart vmalert`. Then delete it and restart vmalert again (`install_vmalert` also clears it) | ntfy priority 5, `rotating_light`, `secsvcs` tag within `group_wait` (30 s) plus one evaluation; email to `+alert@`. After the delete: ntfy `resolved,tada` priority 1 and a resolved email |
| 2 | Dead-man switch | `systemctl stop alertmanager` on secsvcs, then `systemctl start alertmanager` | `deadman`: email + ntfy.sh push within 15 min; a recovery notice after the start |

## Disaster recovery

- Restore a file, a VM or a host: [restore guide](guides/restore.md)
- pve1's SSD died, or its AGE key, private CA, SSH CA or `vars.yml` is gone: [pve1 disaster
  recovery](guides/pve1_recovery.md)
