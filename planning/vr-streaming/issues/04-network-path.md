# 04. Measure and tune the WiFi → pfSense → pve2 stream path

Status: needs-info
Type: task
Repo: homelab
Source: maintainer request 2026-10-12; research in [airlink-research.md](../airlink-research.md)
Blocked by: 01

## Problem

Air Link pushes up to 200 Mbps of latency-sensitive UDP. Here it crosses the AP, then the pfSense
VM on pve1 (VLAN 10 → igc2), before it reaches pve2. Jitter there is felt in the headset. Moonlight
on the Apple TV takes the same path, but at a lower bitrate and with more tolerance.

## Steps

[investigation.md](../investigation.md) part 6, after 01's parts.

## Change

- Use 01's ports to confirm the WiFiTrusted rules (copied from LAN) pass them. Meta publishes none,
  so add a narrow allow rule to the PVE2 interface only if 01 shows a block. Document any rule in
  `docs/guides/router.md.j2`.
- Confirm the mDNS bridge lists the PVE2 interface as well as WiFiTrusted; the router guide only
  adds WiFiTrusted explicitly. If 01 found discovery is broadcast, not mDNS, the bridge won't carry
  it: record what does.
- Set the Air Link bitrate in the headset, not the Oculus Debug Tool, whose encode bitrate has
  been reported to throttle Air Link. Keep the ODT's numeric fields at 0.
- Measure with the Oculus Debug Tool HUD and pfSense CPU on pve1 during a session:
  - at the default bitrate;
  - at 200 Mbps;
  - with H.264 vs H.265 (the ODT's only codec choices; the 3060 Ti has no AV1 encode either).
- AP: give the headset's 5 GHz SSID a fixed, non-DFS 80 MHz channel (Meta warns DFS channels hurt
  Air Link). Record the settings in the router guide.
- Record the bitrate and codec that work in `docs/guides/gaming.md`.

## Acceptance

- A 20-minute session at the chosen bitrate shows no sustained dropped frames on the HUD.
- pfSense CPU stays under 50% on pve1.

## Comments
