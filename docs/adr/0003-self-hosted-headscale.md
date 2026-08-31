# ADR 0003: Self-hosted Headscale instead of managed Tailscale

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

The system needs a WireGuard mesh connecting the VPS, the home VMs, and personal
devices. Managed Tailscale provides this with zero operational overhead, but the
coordination server — node enrollment, ACLs, connection metadata — would live in a
third party's cloud, against the project's self-hosting goal.

## Decision

Run Headscale (the open-source coordination server) on the VPS, with its embedded
DERP relay for peers that can't hole-punch. Standard Tailscale clients everywhere,
pointed at the self-hosted coordination URL. DNS is handled by Unbound local zones
rather than MagicDNS.

## Consequences

- Enrollment data, ACLs, and connection logs stay on owned hardware.
- One more service to update and monitor; CLI-only administration.
- New Tailscale client features can lag until Headscale supports them; notably,
  FreeBSD (pfSense) still lacks `--snat-subnet-routes=false` / kernel-mode pf
  routing, so subnet-routed traffic loses real source IPs at the router — the
  intended group-based ACL matrix is disabled and the active policy is permissive
  pending that upstream fix (tracked as an issue; see the issue's Comments for the
  2026-08-30 re-investigation, which found the ACL *policy engine* itself is not
  FreeBSD-gated — the remaining blocker is narrower than originally believed).
- No Tailscale Funnel or SaaS-side features; public ingress is HAProxy instead.
