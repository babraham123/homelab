# 02. pfSense rules for the camera and WebRTC

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13
Blocked by: 01

## Problem

The camera is a poorly-secured device, and it phones home if allowed to. RTSP to it is
plaintext (spec, leg 1), so the only control is who can reach it. WebRTC to go2rtc
needs `websvcs:8555` reachable from trusted clients.

## Change

Rules in the pfSense GUI. Use an alias `cameras` for the camera IPs.

**On WiFiIoT (VLAN 11) and WiredIoT (VLAN 21), first match wins:**

1. Pass `cameras` → pfSense UDP 123 (NTP) and UDP/TCP 53 (DNS, if the camera insists).
2. Block `cameras` → any. Log it, so you can see what the camera tries to reach.

**On the interfaces of websvcs and homesvcs:**
3. Pass websvcs (`{{ websvcs.ip }}`) → `cameras` TCP 554.
4. Pass homesvcs (`{{ homesvcs.ip }}`) → `cameras` TCP 443, 9000 (Reolink integration;
   9000 is the Baichuan port the HA integration prefers).
5. Pass websvcs → vpnsvcs public IP UDP/TCP 3479 and UDP 49160–49200 (TURN, 04), if
   websvcs's egress is filtered.

**Toward websvcs:**
6. Pass trusted VLANs (10, 20, LAN) and the tailnet (traffic arriving SNATed from the
   router) → `{{ websvcs.ip }}` UDP/TCP 8555.

Record the rules in `docs/networking.md` (VLAN section: "IoT cameras") as the other
VLAN rules are.

## Acceptance

- From the camera's perspective, a WAN check fails: the block log shows its attempts
  to `*.reolink.com` / P2P servers and nothing passes.
- `ffprobe` from websvcs still works; the same command from devtop fails.
- `nc -zv <camera> 443` works from homesvcs and fails from websvcs.
- `nc -zuv {{ websvcs.ip }} 8555` (and TCP) succeed from a phone on trusted WiFi and on
  the tailnet.

## Comments
