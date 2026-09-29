# 05. Tag the infrastructure nodes and set a default node key expiry

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-09-27, from the 0.29.4 upgrade; juanfont/headscale#3122
(`node.expiry`), 0.28 "Tags as identity"
Blocked by: 03

## Problem

`node.expiry` in `src/headscale/headscale.yaml.j2` is `0` (never). A positive value
applies to every registration, and the pfSense package re-runs
`tailscale up --auth-key` on each Tailscale restart, so the router would get a fresh
30-day key every restart and drop off the tailnet a month later. The VPS node was
registered once by hand but has the same exposure on any re-login. Personal devices
(OIDC logins, phones, laptops) therefore never expire either, which is the only
behaviour worth changing.

Tagged nodes are exempt from `node.expiry` and identified by tag rather than user, so
tagging the router and the VPS node lets the default expiry apply to personal devices
only. Tags need `tagOwners` in the policy, which needs the policy loaded (03).

## Change

1. Policy (`src/headscale/headscale_acl.hujson.j2`):
   - add `"tagOwners": { "tag:router": ["group:admin"], "tag:vpnsvcs": ["group:admin"] }`;
   - replace the `admin@` and `public@` sources/destinations with `tag:router` and
     `tag:vpnsvcs` (the public-endpoint rule becomes `src: ["tag:vpnsvcs"]`; the self rules for
     those two users go away);
   - `autoApprovers`: `routes` for the router's subnets and `exitNode` for `tag:router`,
     so re-registration doesn't leave routes unapproved;
   - update `tests` (`src` for a tagged node is `tag:vpnsvcs`, not a user).
   Keep `cousin` user-owned unless it becomes infrastructure too.
2. Create tagged, reusable pre-auth keys:
   ```bash
   headscale preauthkeys create --reusable --expiration 100y --tags tag:router
   headscale preauthkeys create --reusable --expiration 100y --tags tag:vpnsvcs
   ```
3. Re-register: pfSense Tailscale package page, replace the auth key, restart
   Tailscale; on the VPS, `tailscale up --login-server ... --auth-key ... --force-reauth`
   with the same flags as `docs/guides/vpnsvcs.md.j2`. Confirm `headscale nodes list` shows
   the tags and `Expiration` stays `0001-01-01`. Delete the old `admin` and `public`
   users once no node is left under them (`headscale users destroy -i ID`).
4. Set `node.expiry: 30d` in both config templates, deploy, restart headscale. Existing
   personal nodes keep their stored expiry until they next register; force one with
   `tailscale logout && tailscale login ...` to confirm the 30-day value lands.
5. Docs: `docs/guides/vpnsvcs.md.j2` "Create pre-auth key" and "Add public endpoint" use the
   tagged keys; `docs/security.md` VPN boundary notes tagged infra vs. expiring user
   devices.

## Acceptance

- `headscale nodes list`: router and vpnsvcs show `tag:router` / `tag:vpnsvcs`, no expiry;
  every user-owned node registered after step 4 shows an expiry ~30 days out.
- A Tailscale restart on pfSense keeps the routes and exit node approved without a
  manual step.
- Policy `tests` pass and the public endpoint still reaches only the web front doors.

## Comments
