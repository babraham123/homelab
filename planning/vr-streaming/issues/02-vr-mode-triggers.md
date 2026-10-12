# 02. StartVR / StopVR triggers on the gaming VM

Status: needs-info Type: task Repo: homelab Source: maintainer request 2026-10-12 Blocked by: 01

Waiting on 01's answer. The shape below assumes Air Link works headless with the Link app running.

## Change

- `src/nodes/gaming/inventory.yml`: add `StartVR` and `StopVR` to `triggers`. The dispatcher
  allowlist comes from it, so `Dispatcher.ps1.j2` needs no edit.
- `src/nodes/gaming/InstallAutomation.ps1`, tasks kept 1:1 with the triggers:
  - `Homelab_StartVR` (SYSTEM) stops SunshineService, starts OVRService, then starts
    `Homelab_VRClient`.
  - `Homelab_VRClient`: interactive principal for the autologon user. It launches the Link app.
    It isn't a trigger: the dispatcher can't reach it directly.
  - `Homelab_StopVR` (SYSTEM) kills the Link client and stops OVRService.
  - `Homelab_StartSunshine` also runs the StopVR steps first, so the modes stay exclusive. Share
    the stop actions in one variable instead of copying them.
  - `Set-Service OVRService -StartupType Manual`, alongside Sunshine's line in the guide.
- `docs/guides/gaming.md`:
  - replace the manual "Install Oculus App" bullets with a VR mode section covering install, a
    one-time Meta login and headset pairing (both need RDP once), then the triggers;
  - move the mDNS bullet there;
  - note that an RDP session breaks a running VR session.
- `CONTEXT.md`: define **flat mode** and **VR mode** under the gaming node.
- `docs/architecture.md` VM table: gaming is "Windows desktop for PC gaming (Sunshine streaming,
  Air Link VR)".

## Acceptance

- With the VM in flat mode, `ssh autoadmin@gaming StartVR` stops Sunshine, and the headset connects
  over Air Link without anyone touching the VM.
- `ssh autoadmin@gaming StartSunshine` from VR mode ends the Link session, and Moonlight connects.
- `StopVR` leaves neither OVRService nor the Link client running.
- After a reboot, OVRService is stopped.

## Comments
