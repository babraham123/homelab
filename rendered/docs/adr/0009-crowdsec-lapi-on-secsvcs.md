# ADR 0009: CrowdSec decides on secsvcs, the VPS enforces

Status: accepted (2026-10-11)

## Context

The public edge only had static rules: HAProxy's per-source stick tables, geo-blocking and
scanner-path drops on `:80`. HAProxy runs `:443` in TCP mode ([ADR
0002](0002-haproxy-sni-passthrough.md)), so nothing on the public HTTPS path sees a request, and
nothing learns from what the services see. Authelia's `regulation` bans by user, so credential
stuffing across many usernames from one IP was never stopped, and a scanner Traefik answers with 404s
could keep scanning. Only the VPS can drop a source before it reaches the home network.
auth/03 has the full design.

## Decision

- **One CrowdSec engine and Local API (LAPI) on secsvcs**, a quadlet next to VictoriaLogs. The engine
  tails VictoriaLogs (CrowdSec's `victorialogs` data source) rather than running an agent per node:
  Fluent Bit already ships every node's journal there. Traefik's `_msg` is a one-line summary
  (`journald.lua`), so its acquisition rebuilds the JSON line from the kept fields with LogsQL's
  `pack_json`.
- **The VPS enforces.** The firewall bouncer (nftables) on the VPS pulls decisions from the LAPI
  every 10 s and drops banned sources in its own table, ahead of ufw and HAProxy. The LAPI is a
  published TLS port (`8455`, private CA certificate for `crowdsec.SITE`), reached over the tailnet;
  ufw on secsvcs and the Headscale ACL admit only the VPS. It is never an inventory subdomain, which
  would add it to HAProxy's SNI list.
- **Community blocklist**: the LAPI registers with crowdsec.net, pulls its blocklist and shares this
  site's alerts. Its credentials live in `/etc/opt/crowdsec/config`, kept across container rebuilds
  and in secsvcs's backup.
- **Fail open.** The bouncer keeps its last set while the LAPI is unreachable, so a secsvcs reboot
  never takes the sites down; alerts report a dead LAPI or a stale bouncer.
- **fail2ban stays** for SSH on the VPS: local, so it still bans with the tailnet or secsvcs down.
- **WAF (CrowdSec AppSec) runs per node** next to each Traefik, once real client IPs reach Traefik
  (auth/06): the plugin forwards headers and bodies, passwords included, so they never leave the VM.
  The plugin sits on the `websecure` entrypoint, so no router can miss it, in AppSec-only mode: it
  doesn't pull the LAPI's bans, which the VPS already enforces for every public request (LAN and
  tailnet clients are never banned). Each AppSec container is an agent that logs in to the
  LAPI with a client certificate from the private CA (`OU=agent-ou`), so no agent password needs
  registering by hand; each Traefik has its own bouncer key, which AppSec checks with the LAPI.

## Considered

- **A WAF in HAProxy**: needs TLS termination on the VPS, which ADR 0002 rules out.
- **The LAPI on the VPS**: the public host would hold the decision database and the agents' and
  bouncers' credentials, and every node's logs would have to reach it.
- **An agent per node reading the journal**: three more containers with journal access, for logs
  that are already in VictoriaLogs.
- **fail2ban alone**: no shared view across nodes, no Traefik or Authelia scenarios without custom
  filters, no community blocklist.

## Consequences

- secsvcs is in the ban path: while it is down, bans stop being added (the existing ones stay).
  An AppSec container only starts once the LAPI answers, because AppSec rejects a bouncer key it
  can't check, and the plugin blocks on a rejection; while it waits the WAF is off.
- The acquisitions depend on the fields `journald.lua` keeps for Traefik; dropping one breaks the
  parser, which `CrowdsecNotParsing` catches.
- A ban keyed on the wrong address is only as safe as the allowlist: while the router SNATs tailnet
  traffic (router/04), the VPS's requests to the VMs come from the router, which is allowlisted.
