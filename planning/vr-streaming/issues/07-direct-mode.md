# 07. Direct mode: Playnite fullscreen on the TV over HDMI

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; Playnite options in
  [automation-research.md](../automation-research.md#playnite)
Blocked by: 02, 03

The 3060 Ti's HDMI goes straight to the TV and controllers pair with the VM over Bluetooth. Nothing
is streamed: the TV shows the console session, with Playnite's fullscreen app on top.

## Decisions

- **A USB Bluetooth adapter, passed through by vendor:product ID.** pve2 has no radio. Passing
  the whole USB controller over PCIe would take all of pve2's onboard ports, so pass the one
  device. Get one with Bluetooth 5.x LE and a Windows 11 inbox driver (e.g. a Realtek RTL8761B
  stick such as the TP-Link UB500). Avoid BT 4.0 CSR8510 clones. Put it on a USB extension in
  sight of the couch, not in a rear USB 3 port behind the case.
- **Keep the dummy plug; direct mode switches the primary display.** The streaming modes keep the
  dummy plug as primary, so a TV that's off can't leave Sunshine or Link without a display. Direct
  mode makes the TV primary and turns the dummy plug off; stopping restores the streaming layout.
  NirSoft MultiMonitorTool saves both layouts once (`/SaveConfig`) and loads one per mode
  (`/LoadConfig`). It changes the session it runs in, so it runs from admin's interactive tasks.
- **A controller dedicated to the TV.** It pairs with the VM once and never with the Apple TV, so
  no re-pairing.

## Change

- pve2: `qm set <id> --usb0 host=<vid>:<pid>`, so the adapter follows the VM across reboots and
  USB ports. QEMU detaches the host's `btusb` driver on start. Record it in
  `docs/guides/vm_windows.md` next to GPU passthrough.
- `src/nodes/gaming/inventory.yml`: add `StartDirect` and `StopDirect` to `triggers`.
- `src/nodes/gaming/Modes.ps1` (from 02):
  - `Stop-Direct` function: start `Homelab_PlayniteStop` and wait for it, then start
    `Homelab_DisplayStream`. Every other `Start*` mode calls it first. Otherwise Sunshine's own
    Playnite launch hands off to the running instance and exits at once.
  - `StartDirect`: `Stop-VR`, stop SunshineService, `Wait-AdminSession`, then
    `Homelab_DisplayDirect`, waiting for it, then `Homelab_DirectClient`.
  - `StopDirect`: `Stop-Direct`.
- `src/nodes/gaming/InstallAutomation.ps1`: add the two triggers to the mode loop, plus tasks with
  admin's interactive principal, like `Homelab_VRClient`:
  - `Homelab_DirectClient`:
    `C:\Users\admin\AppData\Local\Playnite\Playnite.FullscreenApp.exe --hidesplashscreen`, the
    same command Sunshine runs. `-ExecutionTimeLimit ([TimeSpan]::Zero)`;
  - `Homelab_PlayniteStop`: `Playnite.DesktopApp.exe --shutdown`. It must run in admin's session,
    because from SYSTEM it finds no instance. 06 needs the same task; whichever lands first adds
    it;
  - `Homelab_DisplayDirect` / `Homelab_DisplayStream`: `MultiMonitorTool.exe /LoadConfig` of
    `C:\Homelab\display\direct.cfg` / `stream.cfg`. They live outside `gaming-src`
    because an upload replaces that folder.
- OliveTin: add `('Direct', 'StartDirect')` to 03's loop. This gives a "Start Gaming (Direct)"
  button.
- `docs/guides/gaming.md`, a Direct mode section:
  - the HDMI cable next to the dummy plug, and the adapter on its extension;
  - one-time, at the TV with a keyboard and mouse: install MultiMonitorTool, then save
    `stream.cfg` (dummy plug primary, TV extended) and `direct.cfg` (TV primary, dummy plug off);
  - one-time: update the TV controller's firmware (Xbox Accessories app), then pair it in
    Settings → Bluetooth;
  - the TV's HDMI audio as the default playback device, if Windows doesn't pick it;
  - display off after idle but no sign-in on wake (Settings → Accounts → Sign-in options → "Never"),
    so a controller press brings Playnite back;
  - switching the TV's input is by hand: NVIDIA GPUs don't do HDMI-CEC.
- `CONTEXT.md`: define **direct mode** next to flat and VR mode.

## Acceptance

- "Start Gaming (Direct)" with pve2 off ends with Playnite's fullscreen app on the TV, and a
  Bluetooth controller navigates it with no keyboard or mouse.
- A game launched from Playnite plays on the TV with sound from the TV.
- `StartSunshine` from direct mode closes Playnite cleanly, and Moonlight's Playnite app starts.
- `StartDirect` from flat or VR mode leaves no SunshineService, OVRService or Link client running.
- After the VM reboots, the controller reconnects with no re-pairing.
- `StopDirect` leaves the dummy plug primary, and Moonlight streams it with the TV off.

## Comments

2026-10-17: the hands-on parts (adapter passthrough, display layouts, pairing) are for a human,
but the change waits on 02 and 03, both `needs-info`: `Modes.ps1`, the mode task loop and the
OliveTin button loop it extends don't exist yet.
