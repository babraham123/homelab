# 02. Render-consistency checks in the hook; service-specific validation before install on the node

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 33
Blocked by: 01, 08, script-fixes/01, restructure/01

## Change

The basic lint hook is 08 (unblocked). This ticket adds the checks that need the
inventory or a node.

**Local, in the 08 hook, once their dependencies land:**

1. The install_svcs↔dispatcher consistency check (script-fixes/01).
2. `services.yml` / `nodes.yml` validation (restructure/01).

**On the node, before install** (in each `install_svcs.sh` case, before `cp` into
`/etc/`), using the image already present:

- traefik: `podman run --rm -v <rendered>:/cfg:ro traefik:v3.7 traefik healthcheck --configFile=/cfg/static.yml`
  is a runtime check; for static validation use `traefik validate` if available in your
  version, otherwise start-and-ping in a throwaway network.
- authelia: `authelia config validate`.
- haproxy (vpnsvcs): `haproxy -c -f /root/homelab-rendered/src/haproxy/haproxy.cfg`.
- vmalert: `vmalert -rule=/path/*.yml -dryRun`.
- alertmanager: `amtool check-config`; ntfy-alertmanager: dry start (observability/10).
- Gatus: no validator; start and check `/health`.

Fail the case *before* touching `/etc/opt/<svc>` so a bad render never replaces a
working config. This pairs with homesite/03's release-dir pattern if you later want
rollback for service configs too.

## Acceptance

- A commit whose `install_svcs.sh` case has no dispatcher entry is rejected locally.
- `install_svcs.sh traefik` with a broken static.yml exits non-zero and leaves the
  running config untouched.

## Comments

- 2026-09-26: shellcheck/yamllint/render steps moved to 08 so they don't wait on
  restructure/01.
- 2026-09-27: restructure/01 landed. Both local checks now run inside
  `tools/render_src.sh`: `nodes.yml` `services` must equal the `install_svcs.sh` cases
  (this supersedes the script-fixes/01 dispatcher check, since dispatchers are generated
  from that list), commands must be cases in their scripts, subdomains unique and equal
  to the secsvcs/homesvcs `Host()` rules. The hook only needs to run the render.
- 2026-09-27: 01 and 08 resolved, so every blocker is resolved. The hook
  (`.githooks/pre-commit`) runs `render_src.sh`, so the nodes.yml checks already run in
  it. Untested authelia validate that passes the quadlet's secrets and env so the
  template filter can run, from `src/authelia` in the rendered tree:
  `podman run --rm $(sed -nE 's/^Secret=/--secret=/p; s/^Environment=/--env=/p' authelia.container)
  -v "$PWD":/config:ro -v /etc/opt/authelia/certificates:/certificates:ro
  "$(sed -n 's/^Image=//p' authelia.container)" authelia config validate --config /config/configuration.yml`
