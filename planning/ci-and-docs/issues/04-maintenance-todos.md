# 04. Flesh out the TODOs in maintenance.md, podman.md and proxmox.md

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 36
Blocked by: auth/01, auth/02, backup-and-dr/01, backup-and-dr/09, image-updater/07

## Change

- `docs/maintenance.md` "Upgrade all systems — TODO: router, all VMs, pinned docker
  images": write the yearly procedure — pfSense upgrade (snapshot router VM first),
  `apt full-upgrade` per Debian VM in dependency order (secsvcs last), PVE/PBS point
  releases (`docs/guides/proxmox.md.j2` already has the major-version path), and the
  image-bump procedure (link to the updater and override procedure that
  image-updater/07 writes; a tag bump is edit `Image=`/label → `deploy_src.sh` →
  `install_<svc>`).
- `docs/maintenance.md` "Add a new user — TODO": LLDAP UI steps, groups to assign
  (`authelia_gen_access`, and `telemetry` from auth/02),
  first-login 2FA enrolment, and the OIDC apps that need a first login to create the
  local account (Grafana, HA).
- `docs/guides/podman.md.j2` "Backups — TODO: turn into a script": supersede with the
  orchestrator (backup-and-dr/01) and `podman volume export` as the manual fallback;
  fix `systemctl stop ALL_SERVICES` to a concrete reverse-order list per node.
- `docs/guides/proxmox.md.j2` "PVE / PBS backups — TODO: flesh this out": `/etc/pve`
  and `/etc/proxmox-backup` tarballs, where they go (backup-and-dr/09 table), and that
  PBS's own config must be backed up *outside* PBS.
- `src/victoriametrics/victoriametrics.container.j2`: one-line comment next to the commented
  `--influxListenAddr` saying PVE pushes InfluxDB line protocol to HTTP `/write` instead,
  so nobody "fixes" it (leftover from observability/05).

## Comments
