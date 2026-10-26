# 01. Extract the image updater to podman-image-updater

Status: resolved
Type: task
Repo: podman-image-updater (new), homelab
Source: maintainer request 2026-10-25

## Change

- New repo babraham123/podman-image-updater: `image_updater.py`, stdlib only, reading a JSON
  config instead of the Jinja block that listed each node's images and ntfy settings. The
  `/root/homelab-rendered` paths and the `src/base/ntfy.py` import go. README from ADR 0008,
  example config, systemd unit and timer, tests.
- Homelab: render the config from `src/nodes.jinja`; install the script on each node at a pinned
  commit, checked by sha256; point every caller at the installed path.

## Answer

Done 2026-10-25 (podman-image-updater `ec6da36`; homelab branch `extract-image-updater`).

- **Repo:** `--config` (else `$IMAGE_UPDATER_CONFIG`, else `/etc/image_updater/config.json`),
  `--host`, `--dry-run`, `install SERVICE`, `accept CONTAINER`. Per-image `trivyignore` and
  `build_script`; secrets as `{"env"}`, `{"file"}` or `{"command"}`; a `hosts` map so one file
  serves every node. ntfy is inlined. State dir, metric names and the metrics file are unchanged,
  so existing state and `ImageUpdaterStale` carry over; the lock moves to
  `/var/lib/image_updater/lock`. 24 end-to-end tests against fake podman, skopeo, trivy and
  systemctl.
- **Homelab:** `src/base/podman/image_updater.json.j2` (one `hosts` entry per node, the old ntfy
  routes and deadlines, secrets through `get_secret.sh`). The `image_updater` case in
  `src/base/debian/install_svcs.sh` installs `/usr/local/bin/image_updater` with `fetch_pinned`
  and links `/etc/image_updater/config.json` to the rendered JSON, so a deploy updates the image
  list in place. The unit and the four node `install_svcs.sh` gates call the installed path.
  `tests/image_updater_test.sh` checks the rendered config. `build_lib.sh` stays: only the
  services' `build.sh` files use it.
