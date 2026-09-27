# 04. Route subnets in the kernel on pfSense without SNAT, so LAN hosts see tailnet addresses

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-09-26; tailscale/tailscale#5573, #21060, #21070, #18897;
pfSense Redmine #13905

## Problem

On FreeBSD, tailscaled routes subnet traffic through netstack, which ends the tailnet
connection and opens a new one from pfSense's own address. LAN hosts, pfSense VLAN
rules and Traefik (auth/06) see pfSense instead of the tailnet client.

## Upstream status (checked 2026-09-26)

- `TS_DEBUG_NETSTACK_SUBNETS=0` makes tailscaled write subnet packets to `tailscale0`
  for the kernel to forward. Before v1.104 the FreeBSD router has **no** pf/NAT code,
  so this is no-SNAT routing today. OPNsense's "Disable SNAT" option sets exactly this.
- tailscale/tailscale#21060 (merged 2026-09-01, first in v1.104) adds:
  - the `--snat-subnet-routes` flag on FreeBSD;
  - pf-based SNAT in kernel mode when SNAT is on;
  - forwarding sysctls.

  With SNAT off it never touches pf (`router_freebsd.go`: `wantSNAT` is false), so
  v1.104 isn't needed for this setup. The pf anchor/table reload problem only affects
  kernel mode with SNAT on.
- The pfSense package (`pfsense/FreeBSD-ports` `security/pfSense-pkg-Tailscale`,
  GitHub `devel` as of 2026-03-26, `security/tailscale` 1.94.1) already has the SNAT
  checkbox and `--snat-subnet-routes` rc wiring, commented out pending #5573.

## Change

1. **Snapshot:** back up the pfSense config and take a disk-only `qm snapshot`, as in
   01.
2. **Enable kernel routing:** add `tailscaled_env="TS_DEBUG_NETSTACK_SUBNETS=0"` to
   `/etc/rc.conf.local`. The package rewrites `/usr/local/etc/rc.conf.d/tailscaled` and
   `pfsense_tailscaled` ("DO NOT EDIT"), but neither sets `tailscaled_env`. Restart
   Tailscale from the package page. Confirm with
   `procstat -e $(pgrep tailscaled)`.
3. **Firewall → Rules → Tailscale** (the package's `Tailscale` interface group tab;
   kernel-routed traffic now enters pf on `tailscale0`, where there are no pass rules
   yet):
   - pass IPv4+IPv6 from `100.64.0.0/10` / `fd7a:115c:a1e0::/48` to the advertised
     subnets. The Headscale ACLs already filtered these packets (03), so one broad rule
     is fine;
   - optionally add narrower rules or aliases per tailnet IP for defence in depth or
     logging.
4. **Exit node:** pfSense advertises one (`docs/guides/vpn.md.j2`). Internet-bound
   tailnet traffic now leaves WAN with a 100.x source. Switch Outbound NAT to Hybrid
   and add WAN rules translating `100.64.0.0/10` (and the ULA /48, if IPv6 exit is used)
   to the WAN address.
5. **Verify:**
   - from a phone on mobile data via the tailnet, a LAN host's logs and pfSense's
     state table (Diagnostics → States, filter `100.`) show the phone's 100.x address;
   - exit-node browsing still works;
   - apply a filter change (Status → Filter Reload) and reboot, then recheck both.
6. **Docs:**
   - `docs/guides/router.md.j2`: the env var, Tailscale-tab rules, outbound NAT rule;
   - `docs/networking.md`: tailnet traffic keeps its source IP past the router;
   - auth/06: drop the `.1` gateway entries from Traefik `trustedIPs`.
7. **After v1.104 reaches the package:** check whether the package exposes the SNAT
   checkbox, and if so move from the env var to the supported flag.

## Acceptance

- LAN hosts see tailnet clients' 100.x addresses, and still do after a filter reload and
  a reboot.
- Subnet access and exit-node internet access both work from off-site.

## Comments
