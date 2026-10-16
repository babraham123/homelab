# 05. Home Assistant camera, WebRTC and Frigate integration

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13
Blocked by: 03

## Problem

HA has no camera. It should show:

- live WebRTC from Frigate's bundled go2rtc;
- Frigate events;
- camera controls.

It should work from home, the tailnet and the internet, without HA opening its own
connection to the camera.

## Change

**In the repo (`src/services/home_assistant/configuration.yaml.j2`):**

- **Remove the `go2rtc:` TODO.** HA doesn't talk to go2rtc directly: the Frigate
  integration proxies the stream and signalling through Frigate's authenticated API.
  Check whether HA's built-in go2rtc (`default_config`) needs disabling so it doesn't
  open its own camera sessions. Disabling `go2rtc` in HA's config is the documented
  way.
- **STUN only, no TURN.** There's no TURN server (04, wontfix). Leave
  `web_rtc: ice_servers` unset so the browser uses HA's default STUN. Off-VPN viewers
  whose NAT blocks a direct connection turn on the VPN. For reference:
  - HA returns its ICE servers to every logged-in user
    (`camera/webrtc/get_client_config`), so never put a credential there.
  - Frigate's own UI hardcodes `stun:stun.l.google.com:19302` (`WebRTCPlayer.tsx`).

**In the HA UI:**

- **Frigate integration (HACS).**
  - URL `https://nvr.{{ site.url }}`, with Frigate's own login (leg 5).
  - Its camera entities are the ones on dashboards.
- **Reolink integration.**
  - Host = the camera IP, user `homeassistant` (01).
  - Use it for motion/AI entities, PTZ, siren and light.
  - Disable its camera entities so HA never pulls RTSP from the camera.
- **Advanced Camera Card (HACS)** on a dashboard, with Frigate as the camera engine and
  WebRTC live view.

## Acceptance

Live view starts in under 2 s. `chrome://webrtc-internals` (or the HA app's debug log)
shows the selected candidate pair:

| Client | Expected candidate |
| --- | --- |
| Laptop on trusted WiFi | `host` → `{{ websvcs.ip }}:8555` |
| Phone on the tailnet (mobile data) | `host` via the subnet route |
| Phone on mobile data, no VPN | `srflx` ↔ `srflx` (home public IP) if the carrier's NAT allows; otherwise the VPN, as above |
| Guest on the tailnet | `srflx` ↔ `srflx`, like an off-VPN phone, unless router/03 opens 8555 to guests |

- An off-VPN WebRTC session doesn't move vpnsvcs's `eth0` transmit rate.
- Frigate person events appear in HA as entities and notifications.
- The camera has one RTSP session.

## Comments
