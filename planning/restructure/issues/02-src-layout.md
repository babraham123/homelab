# 02. Restructure src/ into nodes/, services/, base/ and update every path

Status: ready-for-human
Type: task
Repo: homelab
Source: user item 53
Blocked by: 01

## Target layout

```text
src/
  base/        debian/ (incl. msmtprc.j2) podman/ node_exporter/ vm_watchdog/ lib.sh
  clients/     macos/
  nodes/       pve1/ (incl. certificates/) pve2/ router/ vpnsvcs/ secsvcs/ homesvcs/ websvcs/
               devtop/ gaming/   each with its own inventory.yml
  services/    everything else (authelia/ grafana/ traefik/ ...)
  nodes.jinja
```

Shared Traefik config `src/traefik/` → `src/services/traefik/`; per-node `src/<node>/traefik/` stays
under `src/nodes/<node>/traefik/` (the naming trap is then visibly "shared vs node").

## Every path that changes

- `install_svcs.sh` on every node: `cd /root/homelab-rendered/src` + relative `cp` paths
  (`podman/*.sh` → `base/podman/*.sh`, `<svc>/` → `services/<svc>/`, `<node>/traefik` →
  `nodes/<node>/traefik`, `debian/` → `base/debian/`).
- `dispatcher.sh`, `sudoers.j2`, `commands.sh.j2` absolute paths (`/root/homelab-rendered/src/...`)
  on every node, including `src/gaming/Dispatcher.ps1` and the `$(hostname)` lookup in
  `debian/commands.sh install_dispatcher` (`src/nodes/$(hostname)/`).
- `tools/*.sh`: `parse_*` (deleted by 01), `upload_src.sh` router/gaming special cases (`src/router`
  → `src/nodes/router`).
- `.fdignore` globs (`src/grafana/dashboards/*.json`, `src/vmalert/configs/*.yml`).
- `src/olive_tin/config.yaml.j2` if it references script paths; `src/homepage/*` icons.
- `docs/**` references (many), `CONTEXT.md`, `AGENTS.md`, `README.md`.

## Method

`git mv` for history; then render **before and after** against `vars.template.yml` and `diff -r` the
two rendered trees — the only differences allowed are the directory prefixes. Grep the rendered tree
for `homelab-rendered/src/[a-z]` paths that don't exist.

## Acceptance

- Render diff is path-only; a full `deploy_src.sh` + `install_all_svcs` on each container VM
  succeeds.

## Comments

- 2026-09-27: restructure/01 added `src/nodes.yml` and `src/nodes.jinja`.
  Paths to update: `script:` values in `nodes.yml` (relative to `src/`), the
  `node ~ '/install_svcs.sh'`, `debian/install_svcs.sh` and `router/` prefixes in
  `nodes.jinja`, the `{% import 'src/nodes.jinja' ... %}` lines, and the
  `src/${node}/...` paths in `render_src.sh`'s inventory checks.
- 2026-10-10: Moved and every path updated. `nodes.yml` `script:` values are now `nodes/<node>/...`
  or `base/debian/...`; `nodes.jinja` builds `nodes/<node>/install_svcs.sh` and maps `nodes/router/`
  to `/root/router-src/`. Rendered against `vars.template.yml`, the before and after trees are
  identical once the `base/`, `nodes/` and `services/` prefixes are stripped. No
  `homelab-rendered/src/...` path in the render, and no `src/...` path in the repo, points at a
  missing file. Left for a human: the cutover below. Do it in one sitting: after the upload, every
  installed copy that embeds an old `/root/homelab-rendered/src/<dir>` path breaks: dispatcher and
  sudoers, `/etc/containers/containers.conf` (the podman secret driver, so every container with
  secrets fails to start), quadlet and unit `ExecStart*` lines, `/etc/msmtprc`, pve1's orchestrator,
  pve2's hookscript.
  1. `tools/deploy_src.sh`
  2. On every Debian/PVE node (pve1, pve2, secsvcs, homesvcs, websvcs, vpnsvcs on port 2202,
     devtop), as manualadmin, since the old dispatcher's `install_dispatcher` points at the removed
     path: `sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher`
  3. secsvcs, homesvcs, websvcs, vpnsvcs:
     `sudo cp /root/homelab-rendered/src/base/podman/containers.conf /etc/containers`
  4. `ssh autoadmin@NODE install_all_svcs` on secsvcs, homesvcs, websvcs
  5. vpnsvcs: `install_deadman`, `install_fluentbit`; `cp .../src/base/debian/msmtprc /etc`
  6. pve1: `install_cert_notifier`, `install_backup_orchestrator`; the same `msmtprc` copy
  7. pve2: `install_hookscript`
  8. Router and gaming: nothing; their trees land at `/root/router-src` and `C:/Homelab/gaming-src`
     as before
  9. On each node,

     ```bash
     grep -rE "homelab-rendered/src/" /etc /usr/local/bin /var/lib/vz/snippets 2>/dev/null | grep -vE "src/(base|nodes|services)/"
     ```

     prints nothing
- 2026-10-17: the layout moved on after the move: `src/nodes.yml` became per-node
  `src/nodes/<node>/inventory.yml` (`0221a7c`), and deploy/04 (`f20c272`) moved the Mac scripts to
  `src/clients/macos/`, pve1's certificate scripts to `src/nodes/pve1/certificates/`, and `msmtprc`
  to `src/base/debian/msmtprc.j2`. The target layout and step 5 above reflect that. The cutover is
  now part of `notes/apply-since-5a50097.md`: steps 1 (deploy), 3 (dispatchers), 4 (pve1/pve2 host
  services and `msmtprc`) and 11 (vpnsvcs). The hosts are still at `5a50097`, so it hasn't run yet.
