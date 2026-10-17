# 05. Prove a UEVR game over Air Link, injected without a keyboard

Status: needs-info
Type: prototype
Repo: homelab
Source: maintainer request 2026-10-12; research in [uevr-research.md](../uevr-research.md)
Blocked by: 01

Starts once 01 has VR mode working by script.

## Question

With VR mode up, can a flat Unreal Engine game be launched from Playnite in the Link desktop view
and have UEVR injected automatically, with no clicks in the UEVR frontend? The research says
`UEVRInjector.exe --attach=<exe>` does it; this checks it on the VM. 06 automates the answer.

## Steps

[investigation.md](../investigation.md) part 7: install a UEVR nightly and the .NET 6 Desktop
Runtime, pick OpenXR once in the frontend, make Link the active OpenXR runtime, then inject into one
single-player UE game by hand and through a temporary Playnite global script.

## Record under ## Answer

- The UEVR nightly build number, and the test game.
- Whether the Playnite-started `--attach` injects with no clicks, and with which delay after launch
  (none, 3 s, 10 s). Whether the frontend stays running after the game exits.
- Whether injection needs admin when Playnite and the game run as admin's normal token.
- Whether OpenXR on the Oculus runtime works, or the game needs OpenVR/SteamVR. The value of
  `HKLM\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime` when Link is active.
- Controllers: whether Touch input reaches the game only after closing the Link desktop view.
- The profile folder (`%APPDATA%\UnrealVRMod\<exe stem>\`) and whether one profile makes the game
  playable.
- Performance on the 3060 Ti, measured with the Oculus Debug Tool HUD:
  - Native Stereo first; Synchronized Sequential only if Native Stereo glitches;
  - with `VR_PassDepthToRuntime=true`;
  - the `OpenXR_ResolutionScale` and in-game settings that hold the headset refresh rate.

## Comments
