# 05. Quadlet labels, localhost/ images, install-time scan; per-VM rollout

Status: ready-for-agent
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Image references", "Scan gate and overrides",
"Changes, in rollout order" step 4
Blocked by: 03, 04

## Change

- Every quadlet on secsvcs, homesvcs, websvcs:
  - `Image=localhost/<namespace>/<name>:<tag>` (registry host removed, namespace kept);
  - `AutoUpdate=local`, including `postgres` (drop the "No auto-update for data safety"
    comment; its `14-alpine` tag keeps updates within the major version);
  - `Label=homelab.upstream=<full ref>` on pulled images, `Label=homelab.build=<service>`
    on built ones;
  - `Label=homelab.update_last=true` on ntfy, ntfy-alertmanager, alertmanager, vmalert,
    victoriametrics and traefik (secsvcs).
- Each `install_svcs.sh` case downloads and scans (or builds and scans) **before**
  copying the quadlet; a block aborts the install and prints findings plus the
  `accept` command.

## Rollout (human)

One VM at a time: **homesvcs → websvcs → secsvcs**. On each: deploy, run the updater
to load images under the new names and check them, then `install_<svc>` the new
quadlets.

## Acceptance

- The render check from 02 passes for every quadlet.
- On each VM, `podman ps --format '{{.Image}}'` shows only `localhost/` images and every
  service is healthy in Gatus.

## Comments
