# 06. Verify the real client IP reaches Traefik and apps through HAProxy

Status: ready-for-human Type: task Repo: homelab Source: maintainer request
2026-09-26 (copyparty/01 "keep the client IP check"; needed again by vaultwarden/01)

## Problem

Public traffic goes internet → HAProxy on the VPS (TCP, SNI passthrough) → tailnet → Traefik on the
node. If Traefik sees the VPS's tailnet address instead of the client's, three things fail:
- **Authelia regulation** bans the VPS, which locks everyone out, instead of banning the attacker;
- **Vaultwarden's login and admin rate limits** key on one shared IP;
- **logs** (Traefik access logs, observability/02; app logs) can't attribute requests.

## Current state (from the repo)

The plumbing exists:
- HAProxy sends `send-proxy-v2` on every node backend
  (`src/services/haproxy/haproxy.cfg.j2:144-164`);
- Traefik's `web` and `websecure` entrypoints accept PROXY protocol and `X-Forwarded-*` from
  `[vpnsvcs.ip, pve1.subnet.1, pve2.subnet.1]` (`src/services/traefik/static.yml.j2:41-55`). The
  gateway addresses are there because Tailscale subnet routing SNATs (tailscale/tailscale#5573).

Nobody has verified it end to end, and trusting the subnet gateways means anything SNATed through
the router can also assert a client IP.

## Change

- Verify, and fix if broken, the hop from Traefik to the app on each node. Each app must trust
  `X-Forwarded-For` only from Traefik's container IP (`.6`). Record the setting per app:
  - Authelia: trusted proxies;
  - Vaultwarden: `IP_HEADER=X-Forwarded-For`,
    `IP_HEADER_TRUSTED_PROXIES={{ <node>.container_subnet }}.6`;
  - copyparty: `xff-src`.
- Check whether the tailnet SNAT still happens with the current Tailscale version. If not, drop the
  `.1` gateway entries from both `trustedIPs` lists. If it does, note which LAN/VLAN sources can
  reach Traefik via the gateway and whether that matters.
- Document the chain in `docs/networking.md` (ingress section).

## Acceptance

- From a phone on mobile data, a request to `auth.SITE`, `files.SITE` and `vault.SITE` logs the
  phone's public IP in Traefik and in the app.
- From the LAN, the LAN client IP is logged (no HAProxy hop).
- A forged `X-Forwarded-For` sent from the internet is not trusted.
- Six failed Authelia logins for different usernames from the phone get the phone's IP banned by
  CrowdSec (auth/03), not the VPS.

## Recurring check until pfsense/FreeBSD-ports#1462 ships

The no-SNAT routing this ticket relies on is a System Patches change on the router (router/04). A
pfSense-pkg-Tailscale update overwrites it without warning, and Traefik then logs every public client
as the gateway `.1`. Monthly, and after every pfSense or Tailscale package update:
1. `gh pr view 1462 -R pfsense/FreeBSD-ports --json state,mergedAt`, and the installed
   pfSense-pkg-Tailscale version (System → Package Manager → Installed Packages).
2. System → Patches lists the patch as applied. If not, re-apply it and restart Tailscale twice
   (router/04).
3. `procstat -e $(pgrep tailscaled)` on the router shows `TS_DEBUG_NETSTACK_SUBNETS=0`, and
   Traefik's access log shows public clients' own IPs, not `.1`.

When an installed package version includes #1462: delete the patch, leave **SNAT Subnet Routes**
unchecked, repeat check 3, then resolve this ticket and router/04.

## Comments

- 2026-09-26: the SNAT that forces the `.1` gateway entries is removable once router/04 (kernel
  subnet routing without SNAT on pfSense) is done.
- 2026-10-12 agent: repo side done, short of the gateway entries.
  - Chain documented in `docs/networking.md` ("The client IP").
  - **Authelia** has no trusted-proxy setting: `RequestCtxRemoteIP` (v4.39, `internal/middlewares/wrap.go`)
    takes the first `X-Forwarded-For` entry from any peer. Traefik's ForwardAuth passes the entrypoint's
    sanitized header, so internet clients can't forge it; the boundary is who reaches :9091 (secsvcs
    Traefik, and the websvcs and homesvcs VMs per secsvcs `ufw`). Re-enabling Authelia's mTLS
    `client_certificates` (TODO in its config) would narrow it to the Traefiks.
  - **Authelia regulation** is `modes: ['user']`: it bans users, never IPs, so the "bans the VPS"
    failure in the problem statement can't happen. IP bans are CrowdSec's (auth/03 decided
    regulation stays as is), from the client IP in Authelia's and Traefik's logs; acceptance updated
    to match.
  - **Vaultwarden** and **copyparty** aren't installed; vaultwarden/01 and copyparty/01 already carry
    the settings (`IP_HEADER_TRUSTED_PROXIES` / `xff-src` = `.6`). Vaultwarden takes the rightmost
    untrusted `X-Forwarded-For` entry, so it ignores a forged leading entry even from a trusted source.
  - **SNAT** still happens: the pfSense package is on tailscaled 1.94.1 in netstack mode (router/04).
    The `.1` entries stay in both `trustedIPs` lists; any tailnet client routed through pfSense can
    assert a client IP, LAN/VLAN clients can't (inter-VLAN routing doesn't SNAT).
  **Remaining:** the acceptance checks (phone on mobile data, LAN, forged header, CrowdSec IP ban),
  and dropping the `.1` entries from `src/services/traefik/static.yml.j2` once router/04 lands.
- 2026-10-12: router/04's no-SNAT routing is live via the System Patches change (env var confirmed
  with `procstat`). Both Traefik `trustedIPs` lists are now only `vpnsvcs.tailnet_ip` (new var), the
  secsvcs CrowdSec LAPI rule admits the VPS by its tailnet IP, and `docs/networking.md` matches.
  vaultwarden/01, copyparty/01 and auth/03 part B no longer wait on this ticket; it stays open for
  the acceptance checks (`notes/apply-since-5a50097.md` step 16) and the recurring check above.
