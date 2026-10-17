# 09. Drive Headscale ACL groups from LLDAP groups once headscale supports OIDC groups

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-27, 2026-10-14; juanfont/headscale#2366 (open), PR
  juanfont/headscale#3216 "OIDC groups: persist claim and resolve from ACL group: rules" (open, not
  merged as of 2026-10-14)
Blocked by: upstream PR 3216 shipping in a headscale release

## Problem

Headscale can't use OIDC groups in policy rules ([docs:
Limitations](https://headscale.net/stable/ref/oidc/#limitations)). The `groups` claim from Authelia
is only used for the `allowed_groups` login filter (`headscale_access`). So
`src/services/headscale/headscale_acl.hujson.j2` keeps its own copy of group membership:
`group:admin` from `tailscale_admin` and `group:family` from `users` in `vars.yml`, plus a
per-user "reach your own devices" rule and policy tests that name users. That duplicates LLDAP, and
any user missing from `vars.yml` (e.g. `cousin`) silently gets no access once the policy loads
(router/03). Guests are a CLI-created `guest1` user with preauth keys, outside LLDAP entirely.

Goal: every real person, guests included, is an LLDAP user who registers via OIDC, and their tailnet
access follows their LLDAP groups. The only CLI-registered Headscale users left are machines:
`admin` (router and VM nodes) and `public` (the VPS). Adding a person then never touches
`vars.yml` or the ACL template.

PR 3216, as written (2026-10-14):

- Opt-in config: `oidc.groups.enabled: true` and `oidc.groups.domain` (required); the claim is
  `groups` by default.
- Each login replaces the user's stored memberships; a removed group or a login rejected by
  `allowed_groups` drops them. Peers get updated filters without a restart.
- The policy references a synced group as `group:<name>@<domain>`. Synced groups are a separate
  namespace from the policy's `groups` block: a name defined there resolves only from its listed
  members, never from the IdP. An empty synced group is valid and grants nothing.

`autogroup:self` is supported since headscale 0.27.0 (experimental; docs warn it compiles filters
per node, irrelevant at this size). It is destination-only, and its source may not be a tag, host
or IP. 0.29.5 fixed its filters not updating after a user is added or renamed (#3501).

## Change

1. Wait for a headscale release whose changelog includes PR 3216 (check with
   `gh pr view 3216 -R juanfont/headscale --json state,mergedAt` and the release notes); re-check
   the config keys and `group:<name>@<domain>` syntax against the merged version.
2. Upgrade headscale to that release, at least 0.29.5 (see `docs/guides/vpnsvcs.md.j2` "Upgrade").
3. In `headscale.yaml.j2`, enable `oidc.groups` with `domain: "{{ site.url }}"`. `scope` already
   requests `groups`.
4. In LLDAP create `tailscale_admin`, `tailscale_family` and `tailscale_guests`; Authelia's
   `headscale` claims policy already puts `groups` in the id_token.
5. In `headscale_acl.hujson.j2`:
   - Drop the `groups` block. `acls` reference `group:tailscale_admin@{{ site.url }}`,
     `group:tailscale_family@{{ site.url }}` and `group:tailscale_guests@{{ site.url }}`.
   - Replace the per-user self rules (the `admin@`, `public@`, `tailscale_admin` and `users` loop,
     and `guest1@` entries) with one rule:
     `{ "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self:*"] }`.
     `admin` and `public` are untagged users, so it covers them too.
   - Replace the `{{ users[-1] }}@` family test with the same assertions from
     `group:tailscale_family@{{ site.url }}`, and the `{{ tailscale_admin }}@` test likewise with
     `group:tailscale_admin@{{ site.url }}`.
   - Guest test: a test whose `src` resolves to no node fails (`source resolved to no IP
     addresses`), and tests run on every policy load, so a group test needs a member with a node.
     `tailscale_guests` is empty between visits; drop the `guest1@` test and keep the guest
     assertions as a manual router/03 check.
   - Update the header comment: membership comes from LLDAP groups via OIDC.
6. Remove `users` and `tailscale_admin` from `vars.yml` / `vars.template.yml`; keep
   `tailscale_extra_acls`. Update their other readers: `docs/guides/secsvcs.md.j2` "Setup LLDAP"
   and `docs/guides/vpnsvcs.md.j2` "ACL policy".
7. Guests: replace `docs/guides/vpnsvcs.md.j2` "Guest users" (CLI `guest1` and preauth keys) with
   an LLDAP user in `headscale_access` and `tailscale_guests` who signs in via OIDC; revoke by
   removing the groups and deleting their nodes. Delete the `guest1` Headscale user.
8. Migrate existing people: each CLI-registered person re-registers their devices via OIDC; then
   delete their CLI user. `headscale users list` should show only OIDC users, `admin` and `public`.
9. Confirm the group claim is refreshed: log a user out and in after changing their LLDAP groups,
   and check `headscale policy check` passes.

## Acceptance

- Moving a user between LLDAP groups changes their tailnet access after re-login without editing
  `vars.yml` or the ACL template.
- A new LLDAP user in `headscale_access` and `tailscale_family` reaches their own devices and the
  home subnets after their first OIDC login, with no ACL change or reload.
- The only non-OIDC Headscale users are `admin` and `public`.
- `headscale policy check` passes and the router/03 manual checks still hold.

## Comments

- 2026-10-17: needs-info → ready-for-agent: the plan is complete and waits only on PR 3216 (still
  open). headscale v0.29.5, the minimum in step 2, shipped 2026-10-13.
