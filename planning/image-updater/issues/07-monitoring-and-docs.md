# 07. Dead-man alerts, guides, maintenance, development, ADR 0006

Status: ready-for-agent
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Notifications and monitoring", "Changes, in
rollout order" step 6
Blocked by: 05, observability/01

## Change

- vmalert rule in `src/vmalert/configs/homelab.yml` (created by observability/01): last
  success age over 36 h. Use age, not `absent()`, so a powered-off websvcs doesn't alert.
- Gatus external endpoints for the secsvcs and homesvcs heartbeats.
- `docs/guides/podman.md.j2`: remove `systemctl enable --now podman-auto-update.timer`
  (line 38), otherwise a freshly built VM runs both mechanisms.
- The three service guides: updater install and timer.
- `docs/maintenance.md`: override procedure (`.trivyignore` with `exp:` + reason,
  `sudo image_updater.sh accept <container>`), manual builds (`build_novnc`,
  `build_finance_exporter`).
- `docs/development.md` "Add a new service": labels, `Image=localhost/…`, optional
  `.trivyignore`.
- `docs/adr/0007-scanned-image-updater.md`: "Per-VM scanned image updater instead of
  registry auto-update", with the dropped alternatives from the design (zot registry,
  `Pull=newer`, central builds).

## Comments

- 2026-09-27: ADR 0006 is now the node inventory (restructure/01); use the
  next free number.
