# 04. Render everything once, upload only what each node needs

Status: ready-for-agent
Type: task
Repo: homelab
Source: user item 52 / review structure note
Blocked by: restructure/01, restructure/02

## Problem

`upload_src.sh` ships the entire rendered tree to every node: `websvcs` holds pve1's
scripts, the router config, every dispatcher/sudoers, all Traefik routes, all container
IPs and every guide. The whole network map on the least-trusted VM.

## Change

- Keep `render_src.sh` rendering the whole repo in one pass (cross-node variables need
  it).
- `upload_src.sh <node>` assembles a per-node subset before `scp`:
  `src/nodes/<node>/`, `src/base/` (debian, podman, macos as relevant), and the service
  directories that node installs — read from the minimal inventory (restructure/01), or
  until then by parsing `cp <svc>/` lines in `src/<node>/install_svcs.sh`.
  Exclude `docs/`, `probes/`, `LICENSE`, `README.md`, and all other nodes.
- `install_svcs.sh` paths are unchanged (`/root/homelab-rendered/src/...`) because the
  subset preserves the tree shape.
- pve1 additionally gets `src/certificates/` and `src/pve1/`; vpnsvcs gets
  `haproxy/`, `headscale/`.

## Acceptance

- `ls /root/homelab-rendered/src` on websvcs shows only its own node dir, base dirs and
  its services; every `install_<svc>` still works on every node.

## Comments

- 2026-09-27: restructure/01's `src/nodes.yml` lists each node's services, but
  a service name isn't always its directory (vmagent → victoriametrics/, guacd →
  guacamole/, piper/whisper/openwakeword → wyoming/, ntfy-alertmanager → alertmanager/,
  traefik → traefik/ + <node>/traefik/, fluentbit also uses <node>/). Add the dirs as a
  per-service attribute rather than parsing `cp` lines.
