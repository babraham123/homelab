# 06. UEVR mode: StartUEVR trigger, Playnite injection, OliveTin button

Status: needs-info Type: task Repo: homelab Source: maintainer request 2026-10-12; research in
[uevr-research.md](../uevr-research.md) and [automation-research.md](../automation-research.md)
Blocked by: 02, 03, 05

Waiting on 05's answer, mainly the injection delay and whether controllers need the Link desktop
view closed.

## Change

- `src/nodes/gaming/inventory.yml`: add `StartUEVR` to `triggers`.
- `src/nodes/gaming/Modes.ps1` (from 02):
  - `StartUEVR`: the `StartVR` steps, then `Start-ScheduledTask Homelab_UEVRClient`;
  - `Stop-VR` also kills `UEVRInjector` (it never exits on its own after injecting) and starts
    `Homelab_PlayniteStop`, waiting for it before stopping OVRService.
- `src/nodes/gaming/InstallAutomation.ps1`: add `StartUEVR` to the trigger loop, plus two tasks
  with admin's interactive principal, like `Homelab_VRClient`:
  - `Homelab_UEVRClient`: `Playnite.DesktopApp.exe --startdesktop --hidesplashscreen`.
    `--startdesktop` matters: without it, Playnite's "start in fullscreen" setting relaunches it
    as the fullscreen app;
  - `Homelab_PlayniteStop`: `Playnite.DesktopApp.exe --shutdown`, a clean quit. It must run in
    admin's session: Playnite's instance mutex is per session, so from SYSTEM it finds nothing.
- New `src/nodes/gaming/uevr_inject.ps1 -InstallDir <dir> [-Exe <name>] [-Delay <s>]`, uploaded
  with `gaming-src`:
  - exits without injecting unless OVRService is running and
    `HKLM\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime` points at the Oculus runtime. Flat mode runs the
    same Playnite library through Sunshine, and SteamVR can claim the runtime key;
  - resolves the exe as the single `*-Win64-Shipping.exe` or `*-WinGDK-Shipping.exe` under
    `-InstallDir`, unless `-Exe` is given. Not Playnite's `$StartedProcessId`, which for Steam can
    be the UE bootstrap exe;
  - stops any running `UEVRInjector`, then `Start-Process UEVRInjector.exe --attach=<exe>`, and
    returns at once. Playnite runs scripts on its UI thread, so with `-Delay` it starts a hidden
    child `powershell` that sleeps and then launches the injector.
- Playnite (configured by hand; record in the guide): Settings → Scripts → "Execute after a game is
  started", global:

  ```powershell
  if ($Game.Tags.Name -contains 'UEVR') {
      & 'C:\Homelab\gaming-src\uevr_inject.ps1' -InstallDir $Game.InstallDirectory
  }
  ```

  A game with several shipping exes or a delay from 05 gets its own "Execute after a game is
  started" script passing `-Exe` / `-Delay`, with "Execute global script" unticked.
- OliveTin: add `('UEVR', 'StartUEVR')` to 03's loop, which gives a "Start Gaming (UEVR)" button.
- `docs/guides/gaming.md`, in a UEVR mode section under VR mode:
  - install: the .NET 6 Desktop Runtime, the UEVR nightly and its build number (the 1.05 release
    predates UE 5.5/5.6 support), the folder excluded from antivirus;
  - one-time, over Moonlight: pick OpenXR in the UEVR frontend and close it (`--attach` uses the
    saved choice, default OpenVR); in the Link app, Settings → General → "Set Meta Horizon Link as
    active" for OpenXR;
  - marking a game: the `UEVR` tag, and the per-game override;
  - playing: launch from Playnite in the Link desktop view, then close the desktop view so UEVR's
    OpenXR session gets focus and controller input (if 05 confirms);
  - profiles in `%APPDATA%\UnrealVRMod\<exe stem>\`, with the UEVR build they were made on;
    rendering defaults from 05 (Native Stereo, `VR_PassDepthToRuntime=true`);
  - the anti-cheat warning.
- `CONTEXT.md`: define **UEVR mode** next to flat and VR mode.

## Acceptance

- "Start Gaming (UEVR)" with pve2 off ends with the headset connected over Air Link and Playnite
  open in desktop mode in the Link desktop view.
- Launching the 05 test game from Playnite in the headset injects UEVR with its profile, with no
  clicks outside the game.
- A game without the `UEVR` tag launches flat, with no injection.
- In flat mode, a UEVR-tagged game launched from Playnite over Moonlight plays flat, with no
  injection attempt.
- `StartSunshine` from UEVR mode leaves no `UEVRInjector`, Playnite desktop app or OVRService
  running.

## Comments
