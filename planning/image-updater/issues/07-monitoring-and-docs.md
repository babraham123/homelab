# 07. Dead-man alerts, guides, maintenance, development, ADR 0006

Status: resolved Type: task Repo: homelab Source: notes/image-updater-design.md
"Notifications and monitoring", "Changes, in rollout order" step 6 Blocked by: 05, observability/01

## Change

- vmalert rule in `src/services/vmalert/configs/homelab.yml` (created by observability/01): last
  success age over 36 h. Use age, not `absent()`, so a powered-off websvcs doesn't alert.
- Gatus external endpoints for the secsvcs and homesvcs heartbeats.
- `docs/guides/podman.md.j2`: remove `systemctl enable --now podman-auto-update.timer` (line 38),
  otherwise a freshly built VM runs both mechanisms.
- The three service guides: updater install and timer.
- `docs/maintenance.md`: override procedure (`.trivyignore` with `exp:` + reason,
  `sudo image_updater.sh accept <container>`), manual builds (`build_novnc`,
  `build_finance_exporter`).
- `docs/development.md` "Add a new service": labels, `Image=localhost/…`, optional `.trivyignore`.
- `docs/adr/0007-scanned-image-updater.md`: "Per-VM scanned image updater instead of registry
  auto-update", with the dropped alternatives from the design (zot registry, `Pull=newer`, central
  builds).

## Answer

Done 2026-10-11.

- `ImageUpdaterStale` in `src/services/vmalert/configs/homelab.yml`: last success over 36 h, `for:
  1h` (covers a booting websvcs's catch-up run).
- No Gatus heartbeat (dropped 2026-10-11): Gatus alerts only through vmalert's `EndpointDown`,
  the same path as `ImageUpdaterStale`, and the VPS dead-man watches that path. ADR 0008 records
  it under Considered.
- `podman.md.j2`: `podman-auto-update.timer` removed; a new "Image updater" section installs and
  enables the updater before any service. The three service guides point at it and end with a
  `--dry-run`; the vpnsvcs guide adds it to its Podman steps.
- `maintenance.md` "Container images": slots, notification table, overrides, built images, manual
  rollback. `debugging.md` Images, `development.md` (install_svcs gate, "Add a new service"),
  `CONTEXT.md` (image updater, scan gate).
- ADR 0008 (0007 is the VPS metrics ADR): `docs/adr/0008-scanned-image-updater.md`.

## Comments

- 2026-09-27: ADR 0006 is now the node inventory (restructure/01); use the next free number.
