# 02. Restructure src/ into nodes/, services/, base/ and update every path

Status: ready-for-agent
Type: task
Repo: homelab
Source: user item 53
Blocked by: 01

## Target layout

```
src/
  base/        debian/ podman/ macos/ certificates/ node_exporter/
  nodes/       pve1/ pve2/ router/ vpnsvcs/ secsvcs/ homesvcs/ websvcs/ devtop/ gaming/
  services/    everything else (authelia/ grafana/ traefik/ ...)
  nodes.yml
```

Shared Traefik config `src/traefik/` → `src/services/traefik/`; per-node
`src/<node>/traefik/` stays under `src/nodes/<node>/traefik/` (the naming trap is then
visibly "shared vs node").

## Every path that changes

- `install_svcs.sh` on every node: `cd /root/homelab-rendered/src` + relative `cp` paths
  (`podman/*.sh` → `base/podman/*.sh`, `<svc>/` → `services/<svc>/`, `<node>/traefik` →
  `nodes/<node>/traefik`, `debian/` → `base/debian/`).
- `dispatcher.sh`, `sudoers.j2`, `commands.sh.j2` absolute paths
  (`/root/homelab-rendered/src/...`) on every node, including `src/gaming/Dispatcher.ps1`
  and the `$(hostname)` lookup in `debian/commands.sh install_dispatcher`
  (`src/nodes/$(hostname)/`).
- `tools/*.sh`: `parse_*` (deleted by 01), `upload_src.sh` router/gaming special cases
  (`src/router` → `src/nodes/router`), `render_docs.sh` (unaffected).
- `.fdignore` globs (`src/grafana/dashboards/*.json`, `src/vmalert/configs/*.yml`).
- `src/olive_tin/config.yaml.j2` if it references script paths; `src/homepage/*` icons.
- `docs/**` references (many), `CONTEXT.md`, `AGENTS.md`, `README.md`.

## Method

`git mv` for history; then render **before and after** against `vars.template.yml` and
`diff -r` the two rendered trees — the only differences allowed are the directory
prefixes. Grep the rendered tree for `homelab-rendered/src/[a-z]` paths that don't exist.

## Acceptance

- Render diff is path-only; a full `deploy_src.sh` + `install_all_svcs` on each
  container VM succeeds.

## Comments

- 2026-09-27: restructure/01 added `src/nodes.yml` and `src/nodes.jinja`.
  Paths to update: `script:` values in `nodes.yml` (relative to `src/`), the
  `node ~ '/install_svcs.sh'`, `debian/install_svcs.sh` and `router/` prefixes in
  `nodes.jinja`, the `{% import 'src/nodes.jinja' ... %}` lines, and the
  `src/${node}/...` paths in `render_src.sh`'s inventory checks.
