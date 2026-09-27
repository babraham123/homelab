# 06. Verify the real client IP reaches Traefik and apps through HAProxy

Status: ready-for-agent
Type: task
Blocked by: router/04
Repo: homelab
Source: maintainer request 2026-09-26 (copyparty/01 "keep the client IP check"; needed
again by vaultwarden/01)

## Problem

Public traffic goes internet → HAProxy on the VPS (TCP, SNI passthrough) → tailnet →
Traefik on the node. If Traefik sees the VPS's tailnet address instead of the client's,
three things fail:
- **Authelia regulation** bans the VPS, which locks everyone out, instead of banning the
  attacker;
- **Vaultwarden's login and admin rate limits** key on one shared IP;
- **logs** (Traefik access logs, observability/02; app logs) can't attribute requests.

## Current state (from the repo)

The plumbing exists:
- HAProxy sends `send-proxy-v2` on every node backend (`src/haproxy/haproxy.cfg.j2:144-164`);
- Traefik's `web` and `websecure` entrypoints accept PROXY protocol and
  `X-Forwarded-*` from `[vpn.ip, pve1.subnet.1, pve2.subnet.1]`
  (`src/traefik/static.yml.j2:41-55`). The gateway addresses are there because Tailscale
  subnet routing SNATs (tailscale/tailscale#5573).

Nobody has verified it end to end, and trusting the subnet gateways means anything
SNATed through the router can also assert a client IP.

## Change

- Verify, and fix if broken, the hop from Traefik to the app on each node. Each app must
  trust `X-Forwarded-For` only from Traefik's container IP (`.6`). Record the setting
  per app:
  - Authelia: trusted proxies;
  - Vaultwarden: `IP_HEADER=X-Forwarded-For`,
    `IP_HEADER_TRUSTED_PROXIES={{ <node>.container_subnet }}.6`;
  - copyparty: `xff-src`.
- Check whether the tailnet SNAT still happens with the current Tailscale version. If
  not, drop the `.1` gateway entries from both `trustedIPs` lists. If it does, note
  which LAN/VLAN sources can reach Traefik via the gateway and whether that matters.
- Document the chain in `docs/networking.md` (ingress section).

## Acceptance

- From a phone on mobile data, a request to `auth.SITE`, `files.SITE` and `vault.SITE`
  logs the phone's public IP in Traefik and in the app.
- From the LAN, the LAN client IP is logged (no HAProxy hop).
- A forged `X-Forwarded-For` sent from the internet is not trusted.
- Three failed Authelia logins from the phone ban the phone's IP, not the VPS.

## Comments

- 2026-09-26: the SNAT that forces the `.1` gateway entries is removable once
  router/04 (kernel subnet routing without SNAT on pfSense) is done.
