# ADR 0002: HAProxy runs in TCP/SNI-passthrough mode, not as a TLS-terminating edge

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

The Linode VPS is the only public-facing machine and must route traffic for every
service subdomain. The conventional design terminates TLS at the edge proxy, which
would put every service's private keys and all plaintext traffic on the most exposed,
least trusted machine in the system.

## Decision

HAProxy's :443 frontend runs in TCP mode: it reads the SNI from the TLS ClientHello
and routes the still-encrypted stream to the target VM's Traefik over the Tailscale
mesh, with PROXY protocol v2 preserving the client IP. TLS is terminated only on the
destination VM. Rate limiting, geo-blocking, and (on the :80 HTTP frontend)
attack-path filtering still happen at the edge, before any application is reached.

## Consequences

- A VPS compromise exposes traffic metadata (SNI, IPs) but no plaintext and no keys.
- Certificates live only where the services live; ACME stays with Traefik.
- The edge cannot inspect HTTPS request contents — no WAF-style layer-7 filtering
  for encrypted traffic; those protections exist only on the :80 frontend.
- Every backend hop must speak PROXY protocol, and Traefik must trust the VPS and
  gateway IPs explicitly.
