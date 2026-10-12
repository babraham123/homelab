# 01. Record the deployed git SHA per node, without alerting

Status: ready-for-agent Type: task Repo: homelab Source: review finding 45

## Change

- `tools/render_src.sh` writes `$project_dir/DEPLOYED` containing `sha=$(git rev-parse HEAD)`,
  `dirty=$(git status --porcelain | wc -l)`, `rendered_at=$(date -Is)`. `tools/upload_src.sh`
  stages only `src/` paths (deploy/04), so it also copies `DEPLOYED` into the staged
  `homelab-rendered/`.
- `src/base/debian/commands.sh.j2` `install_dispatcher` (runs on every node after upload) copies a
  textfile-collector metric: `homelab_deployed_info{sha="...",dirty="0"} 1` and
  `homelab_deployed_timestamp_seconds <epoch>` into
  `/var/lib/node_exporter/textfile_collector/homelab.prom` (the directory
  `src/base/node_exporter/node_runner.sh` already passes to `--collector.textfile.directory`).
- Grafana table panel: node × sha × dirty × rendered_at, so drift is visible on demand.
- No vmalert rules.

## Acceptance

- After a full `deploy_src.sh`, the panel shows the same `sha` on every node; after deploying to
  one node only, that node's row differs. Nothing alerts.

## Comments

- 2026-10-12 maintainer: record the SHA but don't alert; the DeployDrift, DeployStale and
  DeployDirty rules are dropped.
