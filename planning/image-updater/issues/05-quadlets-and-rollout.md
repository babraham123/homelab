# 05. Quadlet labels, localhost/ images, install-time scan; per-VM rollout

Status: ready-for-human
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Image references", "Scan gate and overrides", "Changes, in
  rollout order" step 4
Blocked by: 03, 04

## Change

- Every quadlet on secsvcs, homesvcs, websvcs:
  - `Image=localhost/<namespace>/<name>:<tag>` (registry host removed, namespace kept);
  - `AutoUpdate=local`, including `postgres` (drop the "No auto-update for data safety" comment; its
    `14-alpine` tag keeps updates within the major version);
  - `Label=homelab.upstream=<full ref>` on pulled images, `Label=homelab.build=<service>` on built
    ones;
  - `Label=homelab.update_last=true` on ntfy, ntfy-alertmanager, alertmanager, vmalert,
    victoriametrics and traefik (secsvcs).
- Each `install_svcs.sh` case downloads and scans (or builds and scans) **before** copying the
  quadlet; a block aborts the install and prints findings plus the `accept` command.

## Rollout (human)

One VM at a time: **homesvcs → websvcs → secsvcs**. On each: deploy, run the updater to load images
under the new names and check them, then `install_<svc>` the new quadlets.

## Acceptance

- The render check from 02 passes for every quadlet.
- On each VM, `podman ps --format '{{.Image}}'` shows only `localhost/` images and every service is
  healthy in Gatus.

## Answer

Code done 2026-10-11; the rollout below is what's left.

- Facts are in the node inventories, not quadlet labels (see 02): `upstream:` on every service with
  an image on secsvcs, homesvcs, websvcs and vpnsvcs, `update_last: true` on traefik,
  victoriametrics, vmalert, alertmanager, ntfy-alertmanager and ntfy (secsvcs).
- Every quadlet, in use or not, has `Image=localhost/…` and `AutoUpdate=local`; postgres gained
  it, and `eclipse-mosquitto` is `library/eclipse-mosquitto`.
- vpnsvcs shares the fluentbit and vmagent quadlets, so it runs the updater too (decided
  2026-10-11), in a 20:00 slot.
- Install-time gate: each node's `install_svcs.sh` runs
  `base/podman/image_updater.py install "$1"` before its `case`, so every case loads and scans its
  images before copying quadlets.

Rollout per node, vpnsvcs included (homesvcs → websvcs → secsvcs → vpnsvcs): add the new secrets
(`secret_update.sh`), deploy, `install_image_updater`, run `/usr/local/bin/image_updater` once,
which loads the images under their new names, then `install_all_svcs` (or each service on
vpnsvcs).

## Comments

- 2026-10-25: the updater is now github.com/babraham123/podman-image-updater, installed by
  `install_image_updater` to `/usr/local/bin/image_updater` at a pinned commit, with its image
  list in `src/base/podman/image_updater.json.j2`. The install-time gate in each `install_svcs.sh`
  is `/usr/local/bin/image_updater install "$1"`; the rollout above uses that path.
