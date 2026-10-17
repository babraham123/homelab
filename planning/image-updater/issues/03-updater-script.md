# 03. Updater script, accept, --dry-run, units, Trivy/skopeo install

Status: resolved
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Per-image pipeline", "Scan gate and overrides", "Scheduling",
  "Notifications and monitoring"
Blocked by: 02

## Change

- `src/base/podman/image_updater.sh.j2` rendering `<node>_images`; skips entries whose quadlet isn't
  in `/etc/containers/systemd`. Pulled-image pipeline exactly as the design's steps 1–8 (state in
  `/var/lib/image_updater/{state,staging,accepted}/`, remote-vs-remote digest compare, Trivy
  `HIGH,CRITICAL --ignore-unfixed`, optional `src/services/<service>/.trivyignore`, `:rollback` tag,
  `podman auto-update --format json`, prune untagged only). Fail the run if the Trivy DB refresh
  fails.
- Subcommands: default run, `--dry-run` (check and scan, no load or restart), `accept <container>`
  (rescan, print findings, record exact digest, notify). `accept` refuses unless invoked via `sudo`
  by `manualadmin`; not added to any dispatcher.
- Runtime guards: wait for boot inside the script (`degraded` is reported, not fatal), 25-minute
  no-new-image deadline on homesvcs/websvcs, `flock -n`.
- Metrics to `/var/lib/node_exporter/textfile_collector/image_updater.prom`: last success timestamp,
  checked/updated/blocked/failed counts, days blocked.
- ntfy notifications with the design's severity table; secsvcs posts to the ntfy container IP,
  homesvcs/websvcs to `https://push.{{ site.url }}`; curl retries. Gatus heartbeat ping on secsvcs
  and homesvcs.
- `image_updater.service` (`Type=exec`, `RuntimeMaxSec=`) and `image_updater.timer`
  (`Persistent=true`; 20:30 homesvcs, 21:00 websvcs, 21:30 secsvcs + 15 min after boot only).
  Installed but **not enabled** here; 06 enables them.
- New `src/base/debian/install_svcs.sh` case installing Trivy and skopeo.
- Secrets: Docker Hub credentials and the ntfy alert token via SOPS (`secrets_template.yaml` entries
  per node).
- Regenerate the affected dispatchers and sudoers.

## Acceptance

- `--dry-run` on homesvcs lists every image with digest-changed / scan result, changes nothing.
- A forced CVE block leaves the old image running and sends priority 3.
- A forced failing update points the name back at `:rollback` and sends priority 4.

## Answer

Done in `src/base/podman/image_updater.sh.j2` (run in place from the rendered tree, like the
other node scripts), `image_updater.service.j2` and `image_updater.timer`.

- Image list: `inv.images[node]` per node, selected by hostname; nodes are
  `inv.nodes_with.install_image_updater`.
- Subcommands: default run, `--dry-run`, `install SERVICE` (05's install-time gate) and
  `accept CONTAINER` (`SUDO_USER` must be manualadmin).
- Scans use JSON output with `--exit-code 3`, so a finding (3) and a Trivy error (anything else)
  are told apart. Notifications list the CVE IDs.
- State: `state/<container>` holds `<digest> <outcome>`; `state/<container>.blocked` holds when the
  gate first blocked it. A blocked digest isn't recorded, so it's rescanned each night against the
  new DB and `.trivyignore`. A missing local image forces a reload even if the digest matches.
- Each image runs in an errexit subshell; any unexpected failure counts as `broken` (priority 5 at
  the end), and registry errors as `error` (no notification).
- Metrics: `image_updater_last_success_timestamp_seconds` (kept from the last clean run on
  failure), `image_updater_images{result}`, `image_updater_blocked_days{container}`.
- Timer slots come from a `slot.conf` drop-in that the `image_updater` case of
  `src/base/debian/install_svcs.sh` writes per hostname. That case installs skopeo and Trivy (Aqua
  apt repo) and the units, and leaves the timer as it was (06 enables it).
- `image_updater` is in `debian_services` for secsvcs, homesvcs, websvcs and vpnsvcs, which
  regenerates the dispatcher, sudoers and OliveTin buttons.
- Secrets: `docker_hub_username`/`docker_hub_token` on all four nodes, `ntfy_alert_token` added
  on homesvcs and vpnsvcs.
- No Gatus heartbeat (dropped 2026-10-11): the completion status already reaches VictoriaMetrics
  through the textfile metrics, and Gatus would alert through the same vmalert path.
- Checked with a stubbed podman/skopeo/trivy harness: dry run changes nothing; a forced CVE block
  keeps the old image and sends priority 3; a forced `failed` from auto-update retags `:rollback`
  and sends priority 4; a DB refresh failure sends priority 5 and keeps the last success time.
  Not run on a VM yet: that's 01's checks and 05's rollout.

## Comments

- 2026-09-27: unblocked; 02 is resolved. The list is `inv.images[node]` from
  `{% import 'src/nodes.jinja' as inv with context %}` (not `<node>_images` in
  `all_vars.yml`): `[{service, container, image, upstream | build}]`, update order.
