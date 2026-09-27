# 08. Rename the vpn node to vpnsvcs

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-26 (user item 48)
Blocked by: 06

## Change

Follow the runbook from 06, in its order.

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
