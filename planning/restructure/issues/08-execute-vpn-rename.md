# 08. Rename the vpn node to vpnsvcs

Status: resolved
Type: task
Repo: homelab
Source: maintainer request 2026-09-26 (user item 48)
Blocked by: 06

## Change

Follow [the runbook from 06](../vpn-rename-runbook.md), in its order.

- **Repo (agent):**
  - `vars.yml`/`vars.template.yml` key `vpn:` → `vpnsvcs:`, and every `{{ vpn.` in
    templates and docs;
  - `git mv src/vpn src/vpnsvcs`;
  - the node lists in `render_src.sh`, `deploy_src.sh`, `upload_src.sh` (port-2202
    case), `CONTEXT.md` and `docs/architecture.md`;
  - SSH configs (`src/macos/ssh.config.j2`, `src/olive_tin/ssh_config.j2`) and OliveTin
    actions;
  - Unbound;
  - monitoring labels.

  One commit, rendered against `vars.template.yml`, so the diff is reviewable.
- **Host (human):**
  - `hostnamectl set-hostname vpnsvcs` and `/etc/hosts` on the Linode;
  - re-issue its SSH host cert with both principals (`vpn.SITE`, `vpnsvcs.SITE`);
  - update `~/.ssh/known_hosts`;
  - registrar record for `vpnsvcs.SITE` only if the new name should be public;
  - `deploy_src.sh`, then `ssh autoadmin@vpnsvcs install_dispatcher` and reinstall the
    node's services.
- **Unchanged:** `vpn.SITE` stays the Headscale `server_url` and the HAProxy `vpn_host`
  SNI, unless 06 chose a re-enrolment campaign.

## Acceptance

- `ssh autoadmin@vpnsvcs install_dispatcher` works, and `grep -rn '{{ vpn\.' src docs`
  finds nothing.
- Every Tailscale client stays connected without re-auth, and `vpn.SITE` still answers
  on 443.
- The vpn node's metrics, Gatus checks and the dead-man checker (observability/10)
  report under the new name, with no gap longer than the rename window.

## Comments

2026-09-27 (restructure/06): the runbook is `planning/restructure/vpn-rename-runbook.md`.
It changes the Host steps above:

- No registrar record: the `*` wildcard covers `vpnsvcs.SITE`.
- Add an Unbound transparent entry instead.
- The first host cert is signed by hand from pve1, connecting by the old name.
- Reinstall only the dispatcher, not the services: the headscale case upgrades
  Headscale.

2026-09-28: runbook phase 1 (repo) is done. None of observability/08, observability/10,
backup-and-dr/10 or restructure/02 had landed, so phase 8 has nothing to rename yet.
The old/new render diff matches the runbook's expected set; `haproxy.cfg` and
`traefik/static.yml` are identical. Beyond the runbook table: `pve1_recovery.md.j2:224`'s
node list, and `pve1.md.j2`'s "services in VPN" lines. No homesite redirect for
`guides/vpn.md`: the maintainer dropped it. Phases 2–7 (human) remain.

2026-09-28: phases 2–7 done by the maintainer; resolved. `git grep -n '{{ vpn\.' src docs`
finds nothing. Follow-up in the repo: short names from pve1 fell back to trust-on-first-use,
because `@cert-authority *.SITE` only matches full names. `install_ssh_ca` now installs
`src/debian/ssh_config` (canonicalize short names, port 2202 for the VPS) as
`/etc/ssh/ssh_config.d/homelab.conf`. Phase 8 is moot: observability/08, observability/10,
observability/12, backup-and-dr/10 and restructure/02 now use `vpnsvcs` directly.
