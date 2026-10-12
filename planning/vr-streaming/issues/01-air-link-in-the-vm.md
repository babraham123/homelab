# 01. Prove Air Link works in the VM with no RDP session

Status: ready-for-human Type: prototype Repo: homelab Source: maintainer request 2026-10-12;
research in [airlink-research.md](../airlink-research.md) and
[automation-research.md](../automation-research.md)

## Question

Can a Quest connect over Air Link and play a Rift game when the VM was started headless, with
OVRService and the Link app started by a script and never through RDP? 02 automates the answer.

## Steps

[investigation.md](../investigation.md) parts 1–5: facts on the VM, pairing over Moonlight with a
discovery capture, a scripted start, a reboot, then stop and switch back to Sunshine.

## Record under ## Answer

- **Paths:** the install root (from `OVRService`'s `PathName`), the client exe's full path, and the
  Oculus OpenXR manifest path.
- **Pairing:** done over Moonlight; whether it survives a VM reboot.
- **Discovery:** mDNS (which service type) or broadcast, from the UDP 5353 / broadcast capture.
- **Ports and protocol** from pfSense states during a session. 04 needs these.
- **Windows network:** the profile (Public or Private) and whether the firewall lets
  `OVRServer_x64.exe` in; what had to change.
- **Service:** does OVRService as installed start the runtime, or is the guide's run-as-admin
  `OVRServer_x64.exe` step still needed? Once paired, does a connection work with only the service,
  or must the Link app run?
- **Interactive task:** that SYSTEM can register and start a task for `admin` with no password;
  its Last Run Result when admin isn't logged on.
- **Display:** works with the dummy plug or TV attached (the baseline); optionally, with none.
- Rough feel, plus the Oculus Debug Tool performance HUD: latency, dropped frames, bitrate.
- If Air Link fails, the reason. Then repeat with the Virtual Desktop Streamer before redesigning
  02, and note whether it finds the PC across the VLAN.

## Comments
