# 05. Prove a UEVR game over Air Link, injected without a keyboard

Status: needs-info Type: prototype Repo: homelab Source: maintainer request 2026-10-12 Blocked by:
01

Starts once 01 has VR mode working by script.

## Question

With VR mode up, can a flat Unreal Engine game be launched from Playnite in the Link desktop view
and have UEVR injected automatically, so nobody has to click in the UEVR frontend on a desktop?
06 automates the answer.

## Steps

- Install the latest UEVR release on the VM. Note the version: nightlies change often, and profiles
  can break across versions.
- Pick one well-supported single-player UE4/UE5 game from the Steam library. Check that it has no
  anti-cheat.
- Go into VR mode the way 01 does. In the headset, open the Link desktop view and start Playnite.
- Launch the game, then inject:
  - first by hand in the UEVR frontend (OpenXR runtime), to get a working baseline and save its
    profile;
  - then from a Playnite "after game started" script that runs the injector with no clicks.

## Record under ## Answer

- How to inject without the GUI: a frontend command-line option to attach to a process name, or a
  wrapper tool (for example Rai Pal) if there isn't one. Also how long to wait after launch before
  injecting.
- Whether OpenXR on the Oculus runtime works, or the game needs OpenVR/SteamVR.
- Where profiles live (`%APPDATA%\UnrealVRMod\<game exe>\`), and whether one profile is enough to
  make the game playable.
- Performance on the 3060 Ti, measured with the Oculus Debug Tool HUD:
  - native stereo vs synchronized sequential rendering;
  - the in-game resolution and upscaler that hold the headset refresh rate.
- Whether the game's window or controller input fights with Link: focus, and the XInput emulation
  through Link's controllers.

## Comments
