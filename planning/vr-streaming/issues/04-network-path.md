# 04. Measure and tune the WiFi → pfSense → pve2 stream path

Status: needs-info Type: task Repo: homelab Source: maintainer request 2026-10-12 Blocked by: 01

## Problem

Air Link pushes ~100–200 Mbps of latency-sensitive UDP. Here it crosses the AP, then the pfSense VM
on pve1 (VLAN 10 → igc2), before it reaches pve2. Jitter there is felt in the headset. Moonlight on
the Apple TV takes the same path, but at a lower bitrate and with more tolerance.

## Change

- Use 01's ports to confirm the WiFiTrusted rules (copied from LAN) pass them. Add a narrow allow
  rule to the PVE2 interface only if 01 shows a block. Document any rule in
  `docs/guides/router.md.j2`.
- Confirm the mDNS bridge includes the PVE2 interface as well as WiFiTrusted. Air Link discovery
  depends on it.
- Measure with the Oculus Debug Tool HUD and pfSense CPU on pve1 during a session:
  - at the default bitrate;
  - at 200 Mbps;
  - with H.264 vs HEVC (the 3060 Ti has no AV1 encode).
- AP: check that the headset gets 80 MHz on the 5 GHz radio (EAP660 HD controller). Prefer a
  fixed, uncongested channel over auto. Record the settings in the router guide.
- Record the bitrate and codec that work in `docs/guides/gaming.md`.

## Acceptance

- A 20-minute session at the chosen bitrate shows no sustained dropped frames on the HUD.
- pfSense CPU stays under 50% on pve1.

## Comments
