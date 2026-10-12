# 01. Upgrade to pfSense CE 2.9.0; replace NAT-PMP / static-port NAT with EIM outbound NAT

Status: resolved Type: task Repo: homelab Source: maintainer request 2026-09-26;
tailscale/tailscale#18035 (https://github.com/tailscale/tailscale/issues/18035)

## Problem

pfSense ≤ 2.8 is a symmetric NAT for UDP, so Tailscale direct connections need one of these
workarounds:
- a static-port outbound NAT rule;
- UPnP/NAT-PMP;
- `randomizeClientPort`, when more than one node sits behind the same NAT.

NAT-PMP lets any LAN device open inbound ports on the WAN, which is unwanted attack surface. pfSense
CE 2.9.0 (and Plus 25.11) adds **endpoint-independent "Port Restricted Cone" outbound NAT**. It is
set per rule and marked "partial experimental". It keeps a client's external IP:port stable across
destinations without static port NAT, so none of the workarounds should be needed (#18035).

## Change

1. **Before the upgrade:**
   - Follow `docs/guides/router.md.j2` "Updates": stop `vm_watchdog` on pve1, back up the pfSense
     config (Diagnostics → Backup & Restore);
   - take a disk-only `qm snapshot` of the router VM on pve1 (the passthrough NICs rule out RAM
     state). This is the rollback.
   - Record the current behaviour for comparison: `tailscale netcheck` on devtop and one LAN client
     (`MappingVariesByDestIP`), and `tailscale status` showing direct vs relay (DERP) per peer.
2. **Upgrade** to CE 2.9.0 per the Netgate upgrade guide. Reinstall packages:
   - mDNS-Bridge, nmap, ntopng, ARPwatch, Service Watchdog, Tailscale, telegraf;
   - the REST API package. In `docs/guides/router.md.j2` "Certificate", change
     `pfSense-2.8.0-pkg-RESTAPI.pkg` to `pfSense-2.9.0-pkg-RESTAPI.pkg`, which the latest
     pfsense-api release ships. Check that the `src/nodes/router/plugins/` telegraf scripts still
     report.
3. **NAT:**
   - Firewall → NAT → Outbound: switch to Hybrid if on Automatic. Add a rule for UDP from the
     LAN/VLAN subnets that run Tailscale, with **Endpoint-independent (Port Restricted Cone)**
     mapping enabled.
   - Delete the static-port outbound NAT rule for Tailscale, if present.
   - Services → UPnP IGD & PMP: **disable** the service and remove its ACLs.
4. **Randomized client port:** the repo sets neither `randomize_client_port` in
   `src/services/headscale/headscale.yaml.j2` / `headscale_private.yaml.j2` (Headscale defaults it
   to `false`) nor `randomizeClientPort` in `headscale_acl.hujson.j2`.
   - Confirm the running Headscale config matches: `grep randomize /etc/headscale/config.yaml` on
     the VPS. Also check any per-client `--port` / `TS_PORT` overrides on LAN nodes (e.g.
     `src/services/headscale/tailscale.service.j2`, the pfSense Tailscale package's listen port).
   - Remove any override that exists only to dodge the symmetric NAT.
5. **Verify** with the same commands as step 1:
   - `MappingVariesByDestIP: false`;
   - peers behind the router show `direct` to each other and to off-site peers (phone on mobile
     data, the VPS);
   - `tailscale ping <peer>` goes direct after the first packets.

   If the experimental EIM mode misbehaves, restore the static-port rule, keep NAT-PMP disabled, and
   record why here.
6. **Docs:**
   - `docs/guides/router.md.j2`: a Tailscale / outbound NAT section describing the EIM rule and why
     UPnP/NAT-PMP is off;
   - `docs/networking.md`: NAT type;
   - `docs/security.md`: no UPnP/NAT-PMP on the LAN.

   Re-enable `vm_watchdog`, and delete the snapshot after a few days of normal operation.

## Acceptance

- pfSense reports 2.9.0, all packages are running, and Service Watchdog covers them.
- UPnP/NAT-PMP is disabled. No static-port Tailscale rule remains, and no client needs
  `randomizeClientPort`.
- `tailscale netcheck` shows endpoint-independent mapping, and LAN peers connect directly.

## Comments

- The upgrade procedure written for ci-and-docs/04 ("Upgrade all systems": pfSense upgrade) should
  reuse this run's notes.
- 2026-10-12, run notes:
  - Upgraded to CE 2.9.0 and reinstalled the packages, including
    `pfSense-2.9.0-pkg-RESTAPI.pkg`.
  - Outbound NAT is Hybrid with one manual rule at the top: WAN, IPv4, UDP, source alias `TS_NETS`
    (pve1, pve2, WiFi and wired trusted), translation to the WAN address, Static Port off,
    Endpoint-independent Mapping on. The rules list shows it as "Randomize Source Port" + "EIM".
  - There was no manual static-port rule to delete. The automatic ISAKMP (UDP 500) static-port rule
    stays; it is for IPsec. UPnP IGD & PMP is disabled.
  - The rule took effect only after a second pass on the config; the first `netcheck` still showed
    `MappingVariesByDestIP: true`. Check that change is applied when repeating this.
  - Verified: `tailscale netcheck` from the trusted WiFi VLAN shows `MappingVariesByDestIP: false`
    and empty `PortMapping`. devtop reaches its peers `direct`, and two LAN nodes pinging the VPS
    at the same time get separate external ports. That rules out the collision reported on the
    Netgate forum (https://forum.netgate.com/post/1230518).
  - Follow-up: delete the router VM's `qm snapshot` after a few days of normal operation.
