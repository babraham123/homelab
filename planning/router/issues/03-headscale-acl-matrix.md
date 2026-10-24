# 03. Re-enable the group-based Headscale ACL matrix

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-09-26; tailscale/tailscale#5573 (Brad Fitzpatrick, 2023-07-18: "ACLs
  are enforced in shared code that's not OS-specific")

## Problem

The group matrix in `src/services/headscale/headscale_acl.hujson.j2` (family / guests / public →
subnets) is commented out, and the policy grants every user `*:*`. It was disabled on the belief
that ACLs don't work for pfSense subnet routes.

## Finding (verified against tailscale `main`, 2026-09-26)

- `net/tstun/wrap.go` `filterPacketInboundFromWireGuard` runs the ACL filter (`filt.RunIn`) on every
  packet arriving from a peer. It has no build tag, so it runs on FreeBSD too.
- netstack takes subnet packets only afterwards, via the `PostFilterPacketInboundFromWireGuard` hook
  (`wgengine/netstack/netstack.go`). The kernel path gets them after the same filter.
- So pfSense drops packets the policy denies, matching on the peer's 100.x address and the subnet
  destination, in both modes. SNAT happens after this and doesn't affect it.
- Linux's iptables rules (`util/linuxfw`) do only accept, anti-spoof, MASQUERADE and
  stateful-filtering, not ACLs. So tailscale/tailscale#13851 isn't needed for this.

## Change

1. Uncomment the matrix. Remove the `*:*` grants it replaces, but keep `admin@`, and keep
   `autogroup:internet` for exit-node users.
2. Extend `tests`, e.g. a guest is denied `lan:*` but accepted on `pve1:443`, and family is accepted
   on `lan:*`.
3. Deploy. `headscale policy check` (or the deploy's validation) must pass.
4. From a guest device, confirm a LAN host is unreachable and the allowed services work. From a
   family device, confirm the LAN is reachable.
5. If a denied flow still gets through, capture `tailscale debug netmap` on pfSense (look for the
   packet filter rules) and record it here before rolling back.
6. Update the "Current state" paragraph in `docs/security.md` and ADR 0003.

## Acceptance

- The matrix is live, its policy `tests` pass, and the manual checks in step 4 match.

## Comments

- 2026-09-27: needs headscale >= 0.29 first (`tests` block; `*` now means tailnet addresses only, so
  subnet access must name the `hosts` CIDRs; `*:0` is rejected since 0.27). The template was
  rewritten accordingly and `group:admin` reads `tailscale_admin` from `vars.yml`. Today
  `policy.path` is commented out in `headscale.yaml.j2` (the template the live config comes from;
  `headscale_private.yaml.j2` is only the pre-OIDC bootstrap config), so no policy is loaded at all;
  step 3 must set it to `/etc/headscale/acl.hujson`. Before that, rename the CLI-created users
  (`admin@`, `jayden@`, `public@`, `guest1@`, `cousin@`) to drop the trailing `@`, or the policy
  fails to resolve them (`headscale users rename -i ID --new-name NAME`). Users were renamed
  2026-09-27. `cousin` gets its rule via `tailscale_extra_acls` in `vars.yml`; `jane` (OIDC user) is
  `tailscale_admin`; `jayden` is family. OIDC-group-driven membership is auth/09.
- 2026-09-27: guest access decided: `group:guests` (the `guest1` user, created per
  `docs/guides/vpnsvcs.md.j2` "Guest users") gets HTTP/HTTPS on secsvcs, websvcs and homesvcs only,
  the same surface as the public endpoint; no exit node, no LAN, no Proxmox/pfSense GUIs. Policy
  `tests` cover admin, family, public and guest.
- 2026-09-27: tagging the router/vpnsvcs nodes and setting `node.expiry` is router/05, blocked on
  this.
- 2026-10-17: supersedes the `policy.path` part of the first comment: `daa2fc6` set `policy.path`
  to `/etc/headscale/acl.hujson` in `headscale.yaml.j2`. Steps 1–2 are done in the repo
  (`89921e9`, `daa2fc6`): the matrix is uncommented and `tests` cover admin, family, public and
  guest. Steps 3–5 (deploy and manual checks) are in `notes/apply-since-5a50097.md` step 11.4.
  Step 6 is open: `docs/security.md` "Current state" still calls the matrix unused, and ADR 0003
  still says pfSense lacks no-SNAT routing.
- 2026-10-24: steps 3–5 moved to `notes/apply-since-5a50097.md` step 18, which follows
  `notes/headscale-acls.md`; step 11 no longer reloads the policy, so the first load comes after
  every node is deployed. The policy gained net_probe's rules (hardware-monitoring/04): `secsvcs`
  → `public@:5201` and ICMP. `docs/guides/vpnsvcs.md.j2` "Telemetry agents" re-installed the
  pre-OIDC `headscale_private.yaml`, which would have dropped OIDC and the policy; it now runs
  `install_svcs.sh headscale`.
