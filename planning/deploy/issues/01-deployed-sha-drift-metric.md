# 01. Record the deployed git SHA per node, without alerting

Status: resolved
Type: task
Repo: homelab
Source: review finding 45

## Change

- `tools/render_src.sh` writes `$project_dir/DEPLOYED`: `sha=$(git rev-parse HEAD)`,
  `dirty=$(git status --porcelain | wc -l)`, `rendered_at=$(date +%s)` (epoch: macOS `date` has no
  `-Is`). Only when rendering from a checkout (`.git` exists); the pre-commit hook renders an index
  export, so `rendered/` gets no `DEPLOYED`. `tools/upload_src.sh` stages only `src/` paths
  (deploy/04), so it also copies `DEPLOYED` into the staged `homelab-rendered/`.
- `tools/upload_src.sh`, right after moving the tree into place, runs
  `src/base/debian/record_deploy.sh` on the node. It writes
  `homelab_deployed_info{sha="...",dirty="0"} 1` and `homelab_deployed_timestamp_seconds <epoch>`
  to `/var/lib/node_exporter/textfile_collector/homelab_deploy.prom` (the directory
  `src/base/node_exporter/node_runner.sh` passes to `--collector.textfile.directory`), and removes
  it when the upload has no `DEPLOYED`. Not `install_dispatcher`: nothing runs it on deploy.
- Grafana "Deployed commits" table on the Homelab alerts dashboard: host × sha × dirty ×
  rendered_at, so drift is visible on demand.
- No vmalert rules.

## Acceptance

- After a full `deploy_src.sh`, the panel shows the same `sha` on every node; after deploying to
  one node only, that node's row differs. Nothing alerts.

## Comments

- 2026-10-12 maintainer: record the SHA but don't alert; the DeployDrift, DeployStale and
  DeployDirty rules are dropped.
- 2026-10-12: done. The spec had `install_dispatcher` writing the metric, but `deploy_src.sh` never
  runs it, so `upload_src.sh` runs `record_deploy.sh` after every upload instead. The file is
  `homelab_deploy.prom`, next to `homelab_backup.prom`. Debian nodes only; the router and gaming VM
  have no node_exporter textfile collector. Acceptance is checked on the next deploy.
