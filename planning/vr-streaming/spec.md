# VR modes on the gaming VM

Two more modes for the gaming VM, both streamed to a Meta Quest headset over Air Link and started
from OliveTin like the Sunshine mode is today:
- **VR mode** plays Oculus (Rift store) PC games.
- **UEVR mode** plays flat Unreal Engine games in VR with [UEVR](https://github.com/praydog/UEVR)
  injected.

Oculus games already work, but only by hand: `docs/guides/gaming.md` says to RDP in, run
`OVRServer_x64.exe` as admin and start the app.

Maintainer requests 2026-10-12. Research: [airlink-research.md](airlink-research.md) (01, 04),
[automation-research.md](automation-research.md) (02, 03), [uevr-research.md](uevr-research.md)
(05, 06). What only the VM and headset can answer is collected in one hands-on session,
[investigation.md](investigation.md), which resolves 01, 04 and 05.

## Modes

The VM runs one mode at a time, because they all stream from the same GPU and NVENC:

| Mode | Trigger | Runs | Client |
|---|---|---|---|
| flat | `StartSunshine` | SunshineService | Moonlight (Apple TV, Mac) |
| VR | `StartVR` | OVRService + the Meta Horizon Link app | Quest, Air Link |
| UEVR | `StartUEVR` | VR mode, plus Playnite in the Link desktop view; Playnite starts the UEVR injector per game | Quest, Air Link |

Starting one mode stops the others. UEVR mode is VR mode with more on top, so it shares VR mode's
start steps and its `StopVR`. `StopSunshine` / `StopVR` stop only their own modes;
`stop_gaming_vm` on pve2 still ends everything.

## Decisions

- **Air Link, not Virtual Desktop or ALVR.** Air Link is free, first-party, and runs Rift games on
  the Oculus runtime directly. ALVR only serves SteamVR. Virtual Desktop (paid) is the fallback if
  01 finds Air Link unworkable in the VM. It also requires the headset on "the same network", so it
  may hit the same cross-VLAN discovery problem.
- **No RDP in the loop.** An RDP session takes the console session off the GPU, and Link then has
  nothing to render to. One-time desktop steps (Meta login, pairing, UEVR's runtime choice) are done
  over Moonlight, which shows the console session. The Link app is started in the autologon user's
  console session by a scheduled task with an interactive principal. SYSTEM can't start it there.
- **One `Modes.ps1`, not chained task actions.** Every trigger's task runs `Modes.ps1 <Trigger>`;
  the shared stop steps are a function in it. Task Scheduler doesn't document how chained actions
  wait or fail.
- **Paths come from the install, not the docs.** Link has shipped under both `Program Files\Oculus`
  and `Program Files\Meta Horizon`, with the client as `OculusClient.exe` or `Client.exe`. 01
  records this VM's; stopping matches the `Support\oculus-client\` folder.
- **OVRService goes to Manual, re-applied by `InstallAutomation`.** In flat mode it would idle on
  the GPU for nothing; a Link repair or update can set it back to Automatic.
- **LAN only.** No Headscale ACL change: Air Link over the mesh would add too much latency.
  Guests keep Moonlight only.
- **Headset on WiFiTrusted.** The trusted VLAN already reaches the pve2 subnet and is in the mDNS
  bridge. The stream is routed by the pfSense VM on pve1 (WiFi → igc1 → pfSense → igc2 → pve2); 04
  checks that this holds up. Meta publishes no ports or discovery protocol, so 01 captures them.
- **UEVR uses OpenXR on the Oculus runtime**, which is the same transport as VR mode. SteamVR
  (OpenVR) is a fallback for a game that needs it, not something to automate.
- **Injection by tag, from one global Playnite script.** The flat game is launched from Playnite,
  which already holds the library, inside the Link desktop view. Playnite's global "Execute after
  a game is started" script runs `uevr_inject.ps1` for games tagged `UEVR`; it calls the official
  `UEVRInjector.exe --attach=<exe>`. There's no OliveTin button per game.
- **Single-player games only.** Injecting into a game with anti-cheat (EAC, BattlEye) risks a ban.

## Out of scope

- SteamVR titles. They run over Link once VR mode is up, with nothing extra to automate.
- Where the Oculus library lives. It moves with the Steam libraries when the games SSD lands
  (backup-and-dr/14).

## Issues

| # | Title | Status | Type | Blocked by |
|---|---|---|---|---|
| [01](issues/01-air-link-in-the-vm.md) | Prove Air Link works in the VM with no RDP session | `ready-for-human` | prototype | |
| [02](issues/02-vr-mode-triggers.md) | `StartVR` / `StopVR` triggers on the gaming VM | `needs-info` | task | 01 |
| [03](issues/03-olivetin-vr-button.md) | OliveTin "Start VR" button | `needs-info` | task | 02 |
| [04](issues/04-network-path.md) | Measure and tune the WiFi → pfSense → pve2 stream path | `needs-info` | task | 01 |
| [05](issues/05-uevr-over-air-link.md) | Prove a UEVR game over Air Link, injected without a keyboard | `needs-info` | prototype | 01 |
| [06](issues/06-uevr-mode.md) | UEVR mode: `StartUEVR` trigger, Playnite injection, OliveTin button | `needs-info` | task | 02, 03, 05 |
