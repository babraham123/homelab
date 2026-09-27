# 03. Updater script, accept, --dry-run, units, Trivy/skopeo install

Status: ready-for-agent
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Per-image pipeline", "Scan gate and overrides",
"Scheduling", "Notifications and monitoring"
Blocked by: 02

## Change

- `src/podman/image_updater.sh.j2` rendering `<node>_images`; skips entries whose
  quadlet isn't in `/etc/containers/systemd`. Pulled-image pipeline exactly as the
  design's steps 1–8 (state in `/var/lib/image_updater/{state,staging,accepted}/`,
  remote-vs-remote digest compare, Trivy `HIGH,CRITICAL --ignore-unfixed`, optional
  `src/<service>/.trivyignore`, `:rollback` tag, `podman auto-update --format json`,
  prune untagged only). Fail the run if the Trivy DB refresh fails.
- Subcommands: default run, `--dry-run` (check and scan, no load or restart),
  `accept <container>` (rescan, print findings, record exact digest, notify). `accept`
  refuses unless invoked via `sudo` by `manualadmin`; not added to any dispatcher.
- Runtime guards: wait for boot inside the script (`degraded` is reported, not fatal),
  25-minute no-new-image deadline on homesvcs/websvcs, `flock -n`.
- Metrics to `/var/lib/node_exporter/textfile_collector/image_updater.prom`: last
  success timestamp, checked/updated/blocked/failed counts, days blocked.
- ntfy notifications with the design's severity table; secsvcs posts to the ntfy
  container IP, homesvcs/websvcs to `https://push.{{ site.url }}`; curl retries.
  Gatus heartbeat ping on secsvcs and homesvcs.
- `image_updater.service` (`Type=exec`, `RuntimeMaxSec=`) and `image_updater.timer`
  (`Persistent=true`; 20:30 homesvcs, 21:00 websvcs, 21:30 secsvcs + 15 min after boot
  only). Installed but **not enabled** here; 06 enables them.
- New `src/debian/install_svcs.sh` case installing Trivy and skopeo.
- Secrets: Docker Hub credentials and the ntfy alert token via SOPS
  (`secrets_template.yaml` entries per node).
- Regenerate the affected dispatchers and sudoers.

## Acceptance

- `--dry-run` on homesvcs lists every image with digest-changed / scan result, changes
  nothing.
- A forced CVE block leaves the old image running and sends priority 3.
- A forced failing update points the name back at `:rollback` and sends priority 4.

## Comments
