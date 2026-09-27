# Scanned image updater

Replaces registry auto-update with a per-VM script that checks upstream, downloads,
scans with Trivy, loads into local storage and runs `podman auto-update` against
`localhost/` images. Nothing in a quadlet can pull from a registry, so an unscanned image
can't reach a container.

Design: `notes/image-updater-design.md` (grilling session 2026-09-12 to 2026-09-14,
status: draft awaiting confirmation). Section names below refer to that file.
Supersedes supply-chain/01.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-pre-implementation-checks.md) | Run the six pre-implementation checks | `ready-for-human` | research |
| [02](issues/02-render-pipeline.md) | `parse_images.sh`, render wiring and the `Image=`/label check | `ready-for-agent` | task |
| [03](issues/03-updater-script.md) | Updater script, `accept`, `--dry-run`, units, Trivy/skopeo install | `ready-for-agent` | task |
| [04](issues/04-build-recipes.md) | Move build recipes into `build.sh`; updater builds on websvcs | `ready-for-agent` | task |
| [05](issues/05-quadlets-and-rollout.md) | Quadlet labels, `localhost/` images, install-time scan; per-VM rollout | `ready-for-agent` | task |
| [06](issues/06-timer-cutover.md) | Disable `podman-auto-update.timer`, enable the updater timer | `ready-for-human` | task |
| [07](issues/07-monitoring-and-docs.md) | Dead-man alerts, guides, maintenance, development, ADR 0006 | `ready-for-agent` | task |
