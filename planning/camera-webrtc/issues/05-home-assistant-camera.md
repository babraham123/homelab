# 05. Home Assistant camera, WebRTC and Frigate integration

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13
Blocked by: 03, 04

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
- **TURN for browsers.** Find out which ICE servers the browser gets on each viewing
  path, and set them to coturn (`stun:` and `turn:` on `{{ vpnsvcs.ip }}:3479`, user
  `webrtc`):
  - **HA frontend / Advanced Camera Card through the Frigate integration.** Check
    whether the card's go2rtc provider reads HA's `web_rtc: ice_servers` config or has
    its own `ice_servers` option.
  - **Frigate's own UI.** Check whether Frigate passes go2rtc's `webrtc.ice_servers` to
    the browser.

  Record the answers here. If a path can't take a TURN server, it falls back to MSE
  over HTTPS, which works off-VPN through the normal ingress, at higher latency.

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
| Phone on mobile data, no VPN | `relay` on `{{ vpnsvcs.ip }}` (or MSE, if the TURN research above says so) |
| Guest on the tailnet | `relay` unless router/03 opens 8555 to guests |

- coturn's log shows the off-VPN session; nothing is relayed on the tailnet.
- Frigate person events appear in HA as entities and notifications.
- The camera has one RTSP session.

## Comments
