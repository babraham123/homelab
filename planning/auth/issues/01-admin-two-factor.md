# 01. Require two_factor for admin subdomains from every network

Status: resolved Type: task Repo: homelab Source: review findings 11, 12

## Problem

`src/services/authelia/configuration.yml.j2:769-791`: one subject (`group:authelia_gen_access`)
matches `*.SITE`, and the `internal`/`vpn` network rule drops everything to `one_factor`. Membership
in the general group therefore grants password-only access from the LAN to OliveTin (root command
execution), the Traefik dashboards, Proxmox and PBS.

## Change

No new LDAP group (maintainer decision 2026-09-26). Who may *use* an admin tool stays an app-level
question (OliveTin ACLs in auth/05, PVE/PBS users, LLDAP admin); Authelia only guarantees that
nobody reaches those tools on a password alone.

- Define the admin subdomain set in `vars.yml` (`authelia.admin_subdomains`): `command`, `secproxy`,
  `homeproxy`, `webproxy`, `pve1`, `pve2`, `pbs2`, `router`, `ldap`, `vmalert`, `alert`,
  `ntfy-alertmanager`.
- One new rule, **above** the `internal`/`vpn` network rule (rules are first-match):

  ```yaml
  - domain: [{% for s in authelia.admin_subdomains %}'{{ s }}.{{ site.url }}',{% endfor %}]
    subject: ['group:authelia_gen_access']
    policy: 'two_factor'        # no network exemption
  ```

  The existing rules remain for everything else, including the one-factor network downgrade. No
  `deny` rule: auth/02 narrows `alert`/`metrics`/`logs`/`push` by group at the Traefik layer, and a
  `deny` here would block those users before they get there.
- Update the OIDC client `authorization_policy` for OliveTin to `two_factor`.
- Record the split (Authelia = factor, app = role) in `docs/security.md#identity`.

## Acceptance

- A `authelia_gen_access` user on the LAN is prompted for 2FA on `command.SITE` and `pve1.SITE`; a
  user with no enrolled second factor cannot get in until enrolled.
- `home.SITE` and the other non-admin subdomains still work at one factor on the LAN.

## Comments

- 2026-09-26 maintainer: dropped the `authelia_admin_access` group; two_factor for the admin set is
  enough.
- 2026-10-12 agent: implemented, not yet applied to secsvcs. Changed from the plan:
  - The admin set is `admin: true` on the services in the node inventory, not
    `authelia.admin_subdomains` in `vars.yml`: `vars.yml` holds personal values and is gitignored,
    while subdomains already live in the inventory. `src/nodes.jinja` derives
    `admin_subdomains` (tested in `tests/nodes_jinja_test.sh`).
  - Flagged: `secproxy`, `homeproxy`, `webproxy`, `ldap`, `vmalert`, `alert`, `command`. Left out
    `pve1`, `pve2`, `pbs2` and `router` (Unbound points them straight at the hosts; nothing routes
    them through Traefik or Authelia, so a rule would do nothing) and `ntfy-alertmanager` (its
    router has no Authelia middleware; ntfy-alertmanager has its own basic auth).
  - Check after applying: on the LAN, `command.SITE` and `secproxy.SITE` ask for the second factor;
    `home.SITE` doesn't.
