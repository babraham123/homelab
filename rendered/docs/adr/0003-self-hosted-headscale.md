# ADR 0003: Self-hosted Headscale instead of managed Tailscale

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

The system needs a WireGuard mesh connecting the VPS, the home VMs, and personal devices. Managed
Tailscale provides this with zero operational overhead, but the coordination server (node
enrollment, ACLs, connection metadata) would live in a third party's cloud, against the project's
self-hosting goal.

## Decision

Run Headscale (the open-source coordination server) on the VPS, with its embedded DERP relay for
peers that can't hole-punch. Standard Tailscale clients everywhere, pointed at the self-hosted
coordination URL. DNS is handled by Unbound local zones rather than MagicDNS.

## Consequences

- Enrollment data, ACLs, and connection logs stay on owned hardware.
- One more service to update and monitor; CLI-only administration.
- New Tailscale client features can lag until Headscale supports them. FreeBSD (pfSense) subnet
  routing SNATs tailnet traffic, so the LAN sees the router's address rather than the client's;
  that was long taken to block the group-based ACL matrix, but ACLs are enforced in the client's
  packet filter before netstack SNATs the flow (verified 2026-09-26 against Tailscale source), and
  the matrix has been the active policy since 2026-10-31. No-SNAT kernel routing works on pfSense
  via `TS_DEBUG_NETSTACK_SUBNETS=0`; tailscale/tailscale#21060 (v1.104) adds the official flag.
- No Tailscale Funnel or SaaS-side features; public ingress is HAProxy instead.
