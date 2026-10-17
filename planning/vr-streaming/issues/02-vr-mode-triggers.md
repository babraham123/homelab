# 02. StartVR / StopVR triggers on the gaming VM

Status: needs-info
Type: task
Repo: homelab
Source: maintainer request 2026-10-12; research in
  [automation-research.md](../automation-research.md)
Blocked by: 01

Waiting on 01's answer: the client path, and whether the service alone starts the runtime. The
shape below assumes Air Link works headless with the Link app running.

## Change

- `src/nodes/gaming/inventory.yml`: add `StartVR` and `StopVR` to `triggers`. The dispatcher
  allowlist comes from it, so `Dispatcher.ps1.j2` needs no edit.
- New `src/nodes/gaming/Modes.ps1 <Trigger>`, run as SYSTEM by every mode task. Shape in
  [automation-research.md](../automation-research.md#shape-for-02):
  - `Stop-VR` function: kill whatever runs from `Support\oculus-client\` (the exe name varies),
    then `Stop-Service OVRService`, then any leftover `OVRServer_x64` / `OVRRedir`.
  - `StartSunshine`: `Stop-VR`, then start SunshineService. `StopSunshine`: stop it.
  - `StartVR`: stop SunshineService (Sunshine closes its running app, so flat-mode Playnite goes
    too), start OVRService, wait up to a minute for admin's session (autologon can lag the boot),
    then `Start-ScheduledTask Homelab_VRClient`.
  - `StopVR`: `Stop-VR`.
  - It throws on failure, so the error lands in the task's Last Run Result and the log.
- `src/nodes/gaming/InstallAutomation.ps1`, tasks kept 1:1 with the triggers:
  - one loop registers `Homelab_<Trigger>` for each mode trigger, running `Modes.ps1 <Trigger>`.
    This replaces the inline `Start-Service` / `Stop-Service` Sunshine tasks;
  - `Homelab_VRClient`: `New-ScheduledTaskPrincipal -UserId admin -LogonType Interactive`, action =
    01's client path, `-ExecutionTimeLimit ([TimeSpan]::Zero)` so Task Scheduler doesn't end the
    client after the default 72 hours. `-RunLevel Highest` only if 01 found the app needs admin. It
    isn't a trigger: the dispatcher can't reach it directly;
  - `Set-Service OVRService -StartupType Manual` on every run, since a Link repair or update can
    put it back to Automatic.
- `docs/guides/gaming.md`:
  - replace the manual "Install Oculus App" bullets with a VR mode section: install, set the
    network profile to Private and allow `OVRServer_x64.exe` if 01 needed it, a one-time Meta login
    and headset pairing over Moonlight (not RDP), then the triggers;
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
- After a reboot, OVRService is stopped and its startup type is Manual.
- `StartVR` right after the VM boots waits for the autologon session instead of failing.

## Comments
