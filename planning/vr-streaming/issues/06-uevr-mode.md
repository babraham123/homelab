# 06. UEVR mode: StartUEVR trigger, Playnite injection, OliveTin button

Status: needs-info Type: task Repo: homelab Source: maintainer request 2026-10-12 Blocked by: 02,
03, 05

Waiting on 05's answer. The shape below assumes the UEVR frontend can be scripted to inject into a
process.

## Change

- `src/nodes/gaming/inventory.yml`: add `StartUEVR` to `triggers`.
- `src/nodes/gaming/InstallAutomation.ps1`:
  - `Homelab_StartUEVR` (SYSTEM) runs the same actions as `Homelab_StartVR`, reused from the shared
    variable rather than copied, then starts `Homelab_UEVRClient`.
  - `Homelab_UEVRClient`: interactive principal for the autologon user. It launches Playnite
    (desktop mode, which works in the Link desktop view).
  - The `StopVR` actions also close the UEVR frontend and Playnite, so `StopVR` and `StartSunshine`
    end UEVR mode too.
- New `src/nodes/gaming/uevr_inject.ps1`: the Playnite "after game started" script that injects
  UEVR into the game's process. It takes the process name as an argument, so each UEVR game's
  Playnite entry calls the same script. It is uploaded with the rest of `gaming-src`. Flat mode
  runs the same Playnite library through Sunshine, so the script exits without injecting when
  OVRService isn't running.
- OliveTin: add `('UEVR', 'StartUEVR')` to 03's loop, which gives a "Start Gaming (UEVR)" button.
- `docs/guides/gaming.md`, in a UEVR mode section under VR mode:
  - installing UEVR, and the version in use;
  - how to mark a game for UEVR in Playnite (a tag, plus the script hook);
  - where profiles live;
  - the anti-cheat warning.
- `CONTEXT.md`: define **UEVR mode** next to flat and VR mode.

## Acceptance

- "Start Gaming (UEVR)" with pve2 off ends with the headset connected over Air Link and Playnite
  open in the Link desktop view.
- Launching the 05 test game from Playnite in the headset injects UEVR with its profile, with no
  clicks outside the game.
- A game without the UEVR tag launches flat, with no injection.
- In flat mode, a UEVR-tagged game launched from Playnite over Moonlight plays flat, with no
  injection attempt.
- `StartSunshine` from UEVR mode leaves no UEVR frontend, Playnite or OVRService running.

## Comments
