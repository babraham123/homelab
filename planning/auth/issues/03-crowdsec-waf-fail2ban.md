# 03. Edge defense: CrowdSec bans at the VPS, CrowdSec WAF in Traefik, fail2ban for SSH

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 14; maintainer request 2026-10-11 (replaces the HAProxy TODO block)

## Problem

The public edge only has static rules. HAProxy (`src/services/haproxy/haproxy.cfg.j2`) rate-limits
per source with 30 s stick tables, geo-blocks, and drops scanner paths on `:80`. It runs `:443` in
TCP mode, so it never sees a request: nothing on the public HTTPS path filters HTTP. Nothing learns
from what the services see:

- Authelia's `regulation` bans by **user** (`modes: ['user']`), so credential stuffing across many
  usernames from one IP is never banned;
- a scanner that Traefik answers with 404s, or a Vaultwarden brute force (vaultwarden/01), can't be
  blocked at the edge, and HAProxy on the VPS is the only place that can drop it;
- fail2ban on the VPS protects sshd (`src/base/debian/jail.local`), but is installed by hand from
  the guide, and its port is appended with `echo`.

## Design

One CrowdSec Local API (LAPI) on secsvcs decides; the VPS enforces at its firewall; each Traefik
runs the WAF. fail2ban stays as the VPS's SSH guard, independent of the tailnet and secsvcs.

| Layer | Where | Does |
| --- | --- | --- |
| HAProxy stick tables, geo-block | VPS | Flood control and countries, unchanged |
| CrowdSec firewall bouncer (nftables) | VPS, host package | Drops banned IPs before HAProxy; pulls decisions from the LAPI |
| fail2ban `sshd`, `recidive` | VPS, host | Bans SSH brute force locally; works with the tailnet or secsvcs down |
| CrowdSec engine + LAPI | secsvcs, container | Reads logs from VictoriaLogs, runs scenarios, holds decisions |
| CrowdSec AppSec (WAF) | secsvcs, homesvcs, websvcs, container | Inspects each request the Traefik plugin forwards |
| Traefik bouncer plugin | secsvcs, homesvcs, websvcs | Blocks banned IPs; forwards requests to the local AppSec |

- **Detection reads VictoriaLogs**, not files: the VictoriaLogs data source (CrowdSec ≥ 1.8), one
  acquisition per program: Traefik access logs (all three VMs; `pack_json` rebuilds the JSON line
  from the fields `journald.lua` keeps) and Authelia; Vaultwarden once vaultwarden/01 lands. No log
  agent per node; Fluent Bit already ships every log.
- **Collections:** `crowdsecurity/traefik` (with `base-http-scenarios`), `crowdsecurity/http-cve`,
  `LePresidente/authelia`, `crowdsecurity/whitelist-good-actors`.
- **Never ban our own addresses:** a allowlist for the LAN subnets, the tailnet range, the VPS's
  tailnet IP and the container subnets. Banning the VPS's tailnet IP would cut off all public
  traffic, the failure auth/06 exists to rule out.
- **AppSec stays on the node.** The plugin forwards headers and bodies (passwords included) to the
  AppSec listener; on the node's Podman network that never leaves the VM. Each node's AppSec
  container is a CrowdSec agent with only the `appsec` acquisition, registered to the LAPI, so WAF
  hits still become alerts and decisions.
- **WAF rules:** `crowdsecurity/appsec-virtual-patching` and `crowdsecurity/appsec-generic-rules`
  in-band (block); `crowdsecurity/appsec-crs` out-of-band (detect only) until a few weeks of logs
  show its false positives (Home Assistant websockets, Grafana and OliveTin APIs, Guacamole), then
  in-band with exclusions.
- **LAPI exposure:** TLS on a published port with the private CA, like LLDAP's 6360, and ufw route
  rules by source for homesvcs, websvcs and the VPS's tailnet IP. Never a subdomain, which would put
  it in HAProxy's SNI list. Each bouncer and agent has its own key from the secsvcs secrets.
- **Fail open.** The firewall bouncer keeps its last set while the LAPI is unreachable; the Traefik
  plugin passes traffic (`crowdsecAppsecUnreachableBlock: false`), so a secsvcs reboot doesn't take
  the sites down.
- **Supply chain:** the Traefik plugin is vendored under `src/services/traefik/plugins-local/` as
  in supply-chain/02; `crowdsec` is an inventory service with an `upstream` image fact and the
  container-hardening directives; the firewall bouncer comes from CrowdSec's apt repo, trusted
  only if its signing key matches the pinned fingerprint.
- **Community blocklist (CAPI):** the LAPI registers with crowdsec.net and pulls the community
  blocklist, sharing this site's alerts (attacker IP, scenario, timestamp) in return. Its online
  API credentials stay in `/etc/opt/crowdsec/config`, which survives container rebuilds and is in
  secsvcs's backup.

## Change

**Part A: decisions and the VPS** (not blocked)

1. `crowdsec` service on secsvcs: engine + LAPI, VictoriaLogs acquisitions, collections, allowlist,
   LAPI TLS port; `install_svcs.sh` case and inventory entry.
2. VPS: a `crowdsec_firewall_bouncer` case (package, LAPI URL and key, nftables mode,
   `deny_action: DROP`).
3. fail2ban as code: a `fail2ban` case on vpnsvcs installs a `jail.local` with `port = 2202` in
   `[sshd]` and a `recidive` jail; the guide calls it instead of the manual steps.
4. Monitoring: vmagent scrapes the engine's and the bouncer's Prometheus endpoints; alerts when the
   bouncer's last pull is older than 10 min or the LAPI is down; a Grafana dashboard.

**Part B: Traefik** (bans key on the real client IP, auth/06)
5. `crowdsec_appsec` container on secsvcs, homesvcs and websvcs; the vendored bouncer plugin; a
   `crowdsec` middleware in `src/services/traefik/dynamic/` on every `websecure` router.
6. CRS in-band after the tuning window.

**Docs:** `docs/security.md#the-edge-haproxy` and `#vps-hardening` describe the layers above; the
vpnsvcs and secsvcs guides get the install steps; an ADR for LAPI on secsvcs and AppSec per node.

## Acceptance

- From an outside IP, a burst of 404s (`crowdsecurity/http-probing`) gets the IP dropped at the VPS:
  `cscli decisions list` on secsvcs shows it, `nft list ruleset` on the VPS has it, and connections
  to `:443` time out.
- Six failed Authelia logins for different usernames from one outside IP ban that IP
  (`LePresidente/authelia-bf_user-enum`, capacity 5).
- `curl 'https://www.SITE/?q=<script>alert(1)</script>'` from outside gets a 403 from the WAF and an
  alert in `cscli alerts list`; the same from the LAN is logged with the LAN IP and not banned.
- With the crowdsec container on secsvcs stopped, every site stays reachable.
- With secsvcs powered off, SSH brute force on 2202 is still banned by fail2ban.
- The VPS's tailnet IP and LAN addresses never appear in `cscli decisions list`.

## Comments

- 2026-10-11: rescoped from "add a TODO block to haproxy.cfg" (stricter stick tables for
  `auth.SITE`, a sticky ban on `https_all`, a longer expiry). The stick tables stay as flood
  control; IP bans move to CrowdSec, which learns from every service's logs. Authelia's
  `regulation` block stays as is.
- 2026-10-11: maintainer decision: join the community blocklist, with alert sharing.
- 2026-10-11: Part A implemented, not yet applied to the nodes: `crowdsec` on secsvcs
  (`src/services/crowdsec/`, LAPI on published port 8080 with a `crowdsec.SITE` certificate),
  `crowdsec_firewall_bouncer` and `fail2ban` on vpnsvcs (`jail.local` moved to
  `src/nodes/vpnsvcs/`), the Headscale ACL and Unbound entries, scrape jobs, `crowdsec.yml` alerts,
  the "CrowdSec" dashboard, guides, security/services docs and ADR 0009. Changed from the design:
  - No HAProxy or sshd acquisitions. HAProxy logs no `httplog`/`tcplog` lines, and every HTTP
    request it forwards is in Traefik's log; sshd's journal isn't shipped (Fluent Bit takes only
    "Homelab:" units), and fail2ban guards SSH.
  - The CAPI credentials stay in the config dir instead of SOPS: the entrypoint registers and
    rewrites them itself, and the dir is already persistent and backed up.
  - Untested: the `pack_json` tail query, the `.yaml.local` bouncer override and the read-only,
    no-capability container are source-derived. Check them with the guides' steps on first apply.
- 2026-10-12 agent: Part B step 5 implemented, not yet applied to the nodes; step 6 (CRS in-band)
  waits for the tuning window, so this is back to the maintainer.
  - Plugin `maxlerebourg/crowdsec-bouncer-traefik-plugin` v1.7.1 vendored without tests or docs;
    the `crowdsec` middleware (`src/services/traefik/dynamic/crowdsec.yml.j2`) is on the
    `websecure` entrypoint rather than on each router, so new routers can't miss it.
  - `crowdsec_appsec` (`src/services/crowdsec/crowdsec_appsec.container.j2.j2`, `.23`) on secsvcs,
    homesvcs and websvcs. Agents log in with client certificates (`appsec-<node>`, `OU=agent-ou`)
    from pve1's cert scripts: the LAPI image pre-registers only one password agent, and certs need
    no `cscli machines add` per node. Bouncer keys are `crowdsec_bouncer_<node>`, registered on
    the LAPI as `traefik_<node>`.
  - CRS is out-of-band and detect only by installing `crowdsecurity/crs` (config and rules)
    without the `appsec-crs` collection, whose `crowdsec-appsec-outofband` scenario would ban.
  - Fail-open details from the plugin source: `updateMaxFailure: -1` and
    `streamStartupBlock: false` (else an unreachable LAPI blocks everything),
    `crowdsecAppsecUnreadableBodyBlock: false` (HTTP/2 uploads without a length), and the AppSec
    unit waits for the LAPI's `/health` before starting, since AppSec answers 401 to a key it
    can't check, which the plugin turns into a 403 for every request.
  - The homelab's machines (VM, PVE, pfSense and VPS tailnet IPs, container subnets) are
    `clientTrustedIps`, so metric and log pushes skip the WAF; LAN devices are still inspected.
  - Untested, check on first apply (secsvcs guide, "Traefik WAF"): the plugin loading
    from `plugins-local`, LAPI client-cert login, the XSS 403, and `cscli alerts list` naming the
    CRS matches.
- 2026-10-12: maintainer decision: the Traefik plugin runs in AppSec-only mode
  (`crowdsecMode: appsec`). Bans stay at the VPS: every public request crosses it, and the LAN and
  tailnet are never banned, so a second ban check in Traefik only added failure modes (stream
  settings, `CrowdsecTraefikBouncerStale`, removed). The per-node bouncer keys stay, since AppSec
  checks them with the LAPI. The design table's "Blocks banned IPs" for the plugin no longer holds.
- 2026-10-12: maintainer decision: the LAPI listens on 8455 instead of 8080
  (`src/services/crowdsec/config.yaml.local`), to avoid future conflicts; not yet applied anywhere,
  so no old rules to remove.
