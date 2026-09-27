# 09. Drive Headscale ACL groups from LLDAP groups once headscale supports OIDC groups

Status: needs-info
Type: task
Repo: homelab
Source: maintainer request 2026-09-27; juanfont/headscale#2366 (open), PR
juanfont/headscale#3216 "OIDC groups: persist claim and resolve from ACL group: rules"
(open, not merged as of 2026-09-27)
Blocked by: upstream PR 3216 shipping in a headscale release

## Problem

Headscale can't use OIDC groups in policy rules
([docs: Limitations](https://headscale.net/stable/ref/oidc/#limitations)). The `groups`
claim from Authelia is only used for the `allowed_groups` login filter
(`headscale_access`). So `src/headscale/headscale_acl.hujson.j2` keeps its own copy of
group membership: `group:admin` from `tailscale_admin` and `group:family` from `users` in
`vars.yml`. That duplicates LLDAP, and any user missing from `vars.yml` (e.g. `cousin`)
silently gets no access once the policy loads (router/03).

PR 3216 makes headscale persist the OIDC `groups` claim per user and resolve
`group:<name>` in the policy against it, merged with any local `groups` definition.

## Change

1. Wait for a headscale release whose changelog includes PR 3216 (check with
   `gh pr view 3216 -R juanfont/headscale --json state,mergedAt` and the release notes).
2. Upgrade headscale (see `docs/guides/vpn.md.j2` "Upgrade").
3. In LLDAP create the groups the policy uses: `tailscale_admin`, `tailscale_family`,
   `tailscale_guests`. Add them to Authelia's `headscale` claims policy (`groups` is
   already in the id_token) so they appear in the `groups` claim.
4. In `headscale_acl.hujson.j2`, drop the local `group:admin` / `group:family` lists and
   reference the LLDAP group names; keep `public@` and the per-user self rules for
   CLI-registered users (`admin`, `public`) that never log in via OIDC.
5. Remove `tailscale_admin` from `vars.yml` / `vars.template.yml` if nothing else uses it.
6. Confirm the group claim is refreshed: log a user out and in after changing their LLDAP
   groups, and check the policy `tests` still pass (`headscale policy check`).

## Acceptance

- Moving a user between LLDAP groups changes their tailnet access after re-login without
  editing `vars.yml` or the ACL template.
- `headscale policy check` passes and the router/03 manual checks still hold.

## Comments
