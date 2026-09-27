# 01. Record the deployed git SHA per node and alert on divergence

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 45

## Change

- `tools/render_src.sh` writes `$project_dir/DEPLOYED` containing
  `sha=$(git rev-parse HEAD)`, `dirty=$(git status --porcelain | wc -l)`,
  `rendered_at=$(date -Is)`.
- `src/debian/commands.sh.j2` `install_dispatcher` (runs on every node after upload) copies a
  textfile-collector metric:
  `homelab_deployed_info{sha="...",dirty="0"} 1` and
  `homelab_deployed_timestamp_seconds <epoch>` into
  `/var/lib/node_exporter/textfile_collector/homelab.prom` (the directory
  `src/node_exporter/node_runner.sh` already passes to `--collector.textfile.directory`).
- vmalert (`homelab.yml`):
  - `DeployDrift`: `count(count by (sha) (homelab_deployed_info)) > 1` for 1h — nodes
    are running different renders.
  - `DeployStale`: `time() - homelab_deployed_timestamp_seconds > 60*86400`.
  - `DeployDirty`: `homelab_deployed_info{dirty!="0"} == 1` for 24h.
- Grafana table panel: node × sha × rendered_at.

## Acceptance

- After a full `deploy_src.sh`, all nodes report the same `sha`; deploying to one node
  only fires `DeployDrift` within the hour.

## Comments
