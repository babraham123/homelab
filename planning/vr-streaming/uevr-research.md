# UEVR over Air Link: injection, runtime, profiles and Playnite hooks

Research for 05 and 06, 2026-10-12. Source read at UEVR `master` 4ee5c6b (= nightly 01143,
2026-08-30), UEVR-Frontend `main` dd6d372 (2025-02-21) and Playnite `master` ecee014 (10.62).
(unverified) marks claims with no primary source or not yet checked on the VM.

## Recommendation

1. **Inject with the official frontend's `--attach=` argument.** It needs no GUI clicks:
   `UEVRInjector.exe --attach=<GameName>-Win64-Shipping.exe`. It was added on 2023-09-30 "for third
   party UEVR usage", and Rai Pal launches UEVR exactly this way. No wrapper tool is needed.
   - It is not headless. The frontend window opens and polls once a second. It injects as soon as
     a process of that name has a titled window and has loaded `d3d11.dll` or `d3d12.dll`, then
     brings the game window back to the front.
   - **The runtime comes from the frontend's saved radio button, and the default is OpenVR.**
     `--attach` has no runtime option. Once per install, open the GUI, pick OpenXR, and close the
     window: the choice is saved on close. Add this step to 06's install docs.
   - **The frontend doesn't exit when the game does.** The attach name is cleared after injection,
     so the "shut down when the attached game closes" check never fires (source reading,
     unverified on the VM). `uevr_inject.ps1` should stop any old `UEVRInjector` first, and
     `StopVR` must stop it (06 already says so).
2. **Use a nightly, not 1.05.** The only stable release, 1.05, dates from 2024-11-16 and predates
   the UE 5.5/5.6 fixes. Nightlies (01143, 2026-08-30) carry them, and uevr.io now claims UE
   4.8–5.6. In 05, change "the latest UEVR release" to "the latest nightly", and record the build
   number in `gaming.md`. The frontend needs the .NET 6 Desktop Runtime (framework-dependent,
   `net6.0-windows`).
3. **Use one global Playnite script, not one per game.** Put it in Settings → Scripts → "Execute
   after a game is started". It runs for every game by default, so it filters on a `UEVR` tag. That
   removes the per-game script hook from 06, so marking a game for UEVR becomes adding the tag.
   - Playnite runs game scripts synchronously in its own PowerShell 5.1 runspace on the main
     thread, so a script that waits blocks the UI. `uevr_inject.ps1` must return at once and leave
     the waiting to the frontend, or to a hidden child process when there's a delay.
   - Exe name: find the single `*-Win64-Shipping.exe` (or `*-WinGDK-Shipping.exe`, which the
     frontend also treats as UE) under `$Game.InstallDirectory`. If a game has more than one, give
     it a per-game "Execute after a game is started" script that passes `-Exe`, and untick its
     "Execute global script".
   - Don't use `$StartedProcessId`. The Steam plugin reports the first process it sees in the
     install directory, which can be the UE bootstrap exe rather than the shipping exe. Playnite
     itself says the variable "might not be available".

   ```powershell
   # Playnite global "Execute after a game is started"
   if ($Game.Tags.Name -contains 'UEVR') {
       & 'C:\Homelab\gaming-src\uevr_inject.ps1' -InstallDir $Game.InstallDirectory
   }
   ```

   `uevr_inject.ps1` then: exits if OVRService isn't running; resolves the exe; stops any running
   `UEVRInjector`; starts `UEVRInjector.exe --attach=<exe>` with `Start-Process`. With a delay, it
   starts a hidden `powershell -Command "Start-Sleep N; Start-Process ..."` instead.
4. **Add an optional per-game delay and measure it in 05.** `--attach` injects within about a
   second of the first window, which is usually during the splash or intro videos. UEVR's own docs
   give no safe point. Chihuahua (third party) waits 10 s and advises getting to the menu first
   because "some games don't like being injected on early boot". UEVR Easy Injector waits 3 s.
   Record per game whether an immediate injection holds.
5. **Add a second guard: the active OpenXR runtime.** UEVR's OpenXR path loads its bundled
   `openxr_loader.dll`, which uses the Khronos `ActiveRuntime` value under
   `HKLM\SOFTWARE\Khronos\OpenXR\1`. Air Link needs that value to point at the Oculus runtime. Set
   it once in the Link app (Settings → General → "Set Meta Horizon Link as active"). The script
   can check that the value contains `oculus` as well as checking OVRService. SteamVR claims the
   key when it is made the active runtime.
6. **The profile path in 05 needs one fix.** The folder is
   `%APPDATA%\UnrealVRMod\<exe name without .exe>\` (for example `...\Foo-Win64-Shipping\`). The
   backend and the frontend both use the exe's stem.
7. **Add a Link-specific step to 05 and the 06 docs: close the Link desktop view after launching
   the game.** UEVR only reads motion controllers while its OpenXR session is FOCUSED. While the
   Link desktop view or menu is in front, the session is at most VISIBLE and receives no XR input.
8. **Rendering: start with Native Stereo**, the default and the docs' "most performant". Use
   Synchronized Sequential only to fix rendering bugs, since it costs more. Avoid AFR. On a 3060
   Ti, lower `OpenXR_ResolutionScale` and in-game settings before changing the mode. Set
   `VR_PassDepthToRuntime=true`, which the docs recommend for the Oculus OpenXR runtime.
9. **The anti-cheat rule stays as written.** UEVR's docs say to assume every multiplayer game has
   anti-cheat and not to inject into it.

## Release, install and how injection works

- **Releases:**
  - Stable: 1.05 (2024-11-16), `UEVR.zip` on the main repo's releases page.
  - Nightly: `praydog/UEVR-nightly`, one release per commit to `master`, numbered (01143 is
    2026-08-30). Each zip is built by `dev-release.yml` from UEVR `master` and the frontend repo's
    default branch.
  - The README still lists UE 4.8–5.4. uevr.io says 4.8–5.6, and the 5.5/5.6 fix commits
    (2025-05 to 2026-07) are only in nightlies.
- **Install:** extract the zip anywhere. Install the .NET 6 Desktop Runtime. Whitelist the folder
  in antivirus ("Anti-viruses may delete files required to run"). The frontend loads its DLLs from
  its own directory (`AppContext.BaseDirectory`), so the working directory doesn't matter.
- **Injection, in order:**
  1. `UEVRPluginNullifier.dll`, if "nullify VR plugins" is on (the default). It disables the game's
     own OpenVR, OpenXR or Oculus plugins.
  2. The runtime DLL: `openxr_loader.dll` or `openvr_api.dll`, from the frontend's `bundled`
     files.
  3. `UEVRBackend.dll`, the mod itself.

  Each step is `LoadLibraryW` through `CreateRemoteThread`. The frontend writes the runtime it
  chose into the game's `config.txt` as `Frontend_RequestedRuntime`, and the backend reads it.
- **Elevation:** the frontend asks for admin only when it can't open the game process. A Steam game
  started from a non-elevated Playnite runs as the same user, so non-admin injection should work
  (unverified).
- **Checklist from the docs before injecting:**
  - Disable HDR.
  - Disable conflicting overlays (RivaTuner, Overwolf, ...).
  - Disable DLSS Frame Generation.
  - Consider turning off Hardware-Accelerated GPU Scheduling.
  - Pass `-nohmd` if the game ships VR plugins.

## Injecting without the GUI

### Official frontend: `--attach=`

`MainWindow()` parses `Environment.GetCommandLineArgs()` and recognises only `--attach=<exe>`.
Behaviour (`Update_InjectStatus`, run every second by a `DispatcherTimer`):

- It strips `.exe` and calls `Process.GetProcessesByName` (case-insensitive). The button reads
  "Waiting for <exe>...".
- **Injectable** (`IsInjectableProcess`) means: 64-bit; a non-empty `MainWindowTitle`; not in the
  built-in filter list; and has loaded `d3d11.dll` or `d3d12.dll`. The UE bootstrap exe never
  matches.
- Once it matches, the frontend injects the nullifier, the runtime and the backend; with
  `FocusGameOnInjection` (default on) it then calls `SwitchToThisWindow` on the game.
- **Settings it uses:** the user-scoped .NET settings saved when the window closes:
  - the OpenXR/OpenVR radio, default OpenVR;
  - "nullify VR plugins", default on;
  - "focus game on injection", default on.

  They live in a per-user `user.config` (exact `%LOCALAPPDATA%` path unverified). Moving the UEVR
  folder or upgrading it may reset them (unverified).
- **No dialogs on this path** apart from the injector's error boxes. The "VR plugins detected" and
  "not an Unreal Engine title" warnings only fire when a process is picked in the dropdown. The
  Virtual Desktop warning only fires if `VirtualDesktop.Streamer` is running.
- **Doesn't exit with the game.** "Shutdown if attached game closes" (2023-10-09) checks that the
  attach name is set, but the name is set to `null` straight after injecting.

### Third-party tools

| Tool | How it injects | Scriptable | Status | Verdict |
|---|---|---|---|---|
| Rai Pal | Runs `UEVRInjector.exe --attach={{GameExecutableName}}` (rai-pal-db mod definition) | Its own GUI launcher | Active (v0.23.0, 2026-10-06) | Same mechanism as calling `--attach` directly; adds a second library app |
| Chihuahua (keton) | Spawns the game itself, waits `--delay` s (default 10), then injects; `--runtime OpenVR\|OpenXR`, `--uevr-build Nightly\|Release`; exits with the game | Yes, console CLI | Last push 2024-06-23 | Launch-based, not attach-based: it would bypass Playnite's Steam launch; stale |
| UEVR Easy Injector (UEVR Deluxe, oduis) | Own frontend, no classic UEVR install; `/launch:<id>` launches a game from its own scanned library; 3 s default pre-injection delay; switches the OpenXR runtime itself; online profile database | Only by its own game IDs | Active (2026-10-11) | A second launcher and library next to Playnite; non-commercial licence |
| Custom UEVR Injector (mirudo2) | Fork of the frontend with auto-inject and auto-close toggles | GUI settings, no documented CLI | Last push 2025-06-13 | No advantage over `--attach` |

## Runtime selection

- **OpenXR or OpenVR:** chosen per injection by the frontend radio button. UEVR's docs: "OpenVR
  usually has the highest compatibility, but OpenXR usually gives higher performance when it works,
  especially if the headset has a native OpenXR runtime". OpenVR needs SteamVR.
- **How the OpenXR runtime is picked:** UEVR injects the standard Khronos loader
  (`openxr_loader.dll`), and UEVR has no runtime picker of its own. The loader reads
  `HKEY_LOCAL_MACHINE\SOFTWARE\Khronos\OpenXR\1`, value `ActiveRuntime`, which holds the full path
  to the runtime's JSON manifest. `XR_RUNTIME_JSON` overrides it, but it would have to be in the
  game's environment, and nothing here sets that. The Oculus manifest is
  `C:\Program Files\Oculus\Support\oculus-runtime\oculus_openxr_64.json` (unverified on the VM).
- **Making Link the active runtime:** Meta's docs: in the Meta Horizon Link app, Settings →
  General, next to OpenXR Runtime, select "Set Meta Horizon Link as active". The button greys out
  once it is active.
- **Oculus/Link support:**
  - UEVR's docs recommend depth integration "on Oculus headsets when using OpenXR with the native
    Oculus OpenXR runtime" (`VR_PassDepthToRuntime`).
  - uevr.io lists Rift CV1, Rift S, Quest 2 and Quest Pro among tested headsets.
  - UEVR issue #409 (2026-03): Air Link was the only streamer that drew UEVR's 2D-screen quad
    correctly; Virtual Desktop and SteamVR didn't.
  - Nothing in the docs says Link is unsupported. The Virtual Desktop special cases in the OpenXR
    runtime code don't apply.

## Profiles

- **Location:** `%APPDATA%\UnrealVRMod\<exe stem>\`. The backend's `get_persistent_dir()` uses the
  stem of the game's module path, and the frontend uses `Process.ProcessName`. Both drop `.exe`.
- **Contents:**
  - `config.txt`: INI-style `key=value`, the UI settings, for example `VR_RenderingMethod`,
    `VR_AimMethod`, `OpenXR_ResolutionScale`, `Frontend_RequestedRuntime`.
  - `cameras.txt`: saved camera offsets.
  - `user_script.txt`: console commands run at startup, created by hand.
  - `cvars_standard.txt` and `cvars_data.txt`: CVars.
  - `uobjecthook/`: motion-control and 6DoF attachments.
  - `plugins/` (DLLs) and `scripts/` (Lua).
  - `log.txt` and `imgui.ini`.

  Global plugins go in `%APPDATA%\UEVR\plugins`.
- **Sharing:**
  - Export: "Export Config" zips the game folder into `%APPDATA%\UnrealVRMod\ExportedConfigs\
    <exe stem>.zip`.
  - Import: "Import Config" takes a zip, uses its file name as the game folder name, unwraps a
    nested zip, and asks for confirmation if the zip contains a DLL. A connected game is told to
    reload.
  - Scripted equivalent: `Expand-Archive` into the game folder before launch.
  - Profiles in the wild are shared on the Flat2VR Discord and in UEVR Easy Injector's database
    (community).
- **Version compatibility:** no official statement.
  - `config.txt` keys are read by name, so plain settings should carry across builds (unverified).
  - Profiles with plugin DLLs or Lua scripts depend on the plugin API of the build they were
    written for.
  - Record the UEVR build next to each saved profile.
- **One profile per game is the unit.** Whether it alone makes a game playable is a per-game
  question for 05. Some games also need a `-nohmd` launch option or deleted VR plugins.

## Rendering: Native Stereo vs Synchronized Sequential

| Mode | How | Cost | Artifacts | Use |
|---|---|---|---|---|
| Native Stereo (default) | UE's own stereo pipeline, both eyes in one frame | Lowest; docs: "performs the best (usually)" | Can crash or glitch in some games; TAA, DLSS and FSR2 intact | First choice |
| Synchronized Sequential | Two full frames per engine tick, world paused between them; "Skip Draw" (default) or "Skip Tick" | Docs: "gives worse performance than Native Stereo" (roughly a second full render per tick, est.) | TAA and temporal ghosting; turn motion blur off | Fallback when Native Stereo glitches |
| AFR | Eyes on alternate frames, world advances between them | Cheapest | Eye desync, "usually nausea" | Don't use |

- For a 3060 Ti there is no official guidance beyond "lower the in-game settings, lower the
  resolution in the UEVR interface". On OpenXR that is `OpenXR_ResolutionScale`.
- Docs: if a game is capped at 60 fps, disable ASW so the runtime doesn't halve it.
  `VR_UncapFramerate` defaults to on.
- The frame rate to hold and the upscaler are per game; measure them in 05.

## Injection timing

- **Frontend:** no fixed delay. It injects on the first one-second poll where the target has a
  titled window and a D3D11/12 module loaded, and it doesn't retry once it has injected.
- **Backend:** finds the engine itself after loading. If XInput isn't loaded yet, its hook keeps
  looking for up to 10 seconds. It logs "engine tick hasn't been called in over a second. Is the
  game loading?" when the game is still loading.
- **Docs:** no recommended point. Third-party practice:
  - Chihuahua: 10 s default; "click through intro cinematics and get to the menu or load a save
    before that happens. Some games don't like being injected on early boot."
  - UEVR Easy Injector: 3 s default, user-adjustable.
- **Playnite's "started" event fires early.** For Steam games it fires when the first process
  appears in the install directory (`ProcessMonitor.TreeStarted`), before the game has a window.
  Starting the frontend from the script at that moment is fine, because it waits for a window.

## Playnite scripting

- **The feature:**
  - Per game: the edit dialog's Scripts tab, "Execute after a game is started", with an "Execute
    global script" checkbox, on by default (`UseGlobalGameStartedScript = true`).
  - Global: Settings → Scripts, same label.
  - Order for "started" (Post): game → emulator → global.
- **Variables:**
  - All game scripts get `$PlayniteApi` and `$Game`, a copy of the library entry. `$Game` has
    `.Tags` (with `.Name`), `.TagIds` and `.InstallDirectory`.
  - The started script also gets `$SourceAction`, `$SelectedRomFile` and `$StartedProcessId`.
  - Macros such as `{InstallDir}` are expanded in the script text (`game.ExpandVariables`).
- **Runtime:**
  - An in-process Windows PowerShell 5.1 runspace (PowerShell 6+ isn't supported), one per game.
  - `ExecutionPolicy Bypass`; `$ErrorActionPreference = 'Stop'`. A thrown error shows a dialog,
    "Failed to execute game script".
  - The working directory is the game's install directory if it exists.
  - It runs synchronously on the main thread: "blocks other execution, including the UI".
- **Passing the process name:** there's no exe variable. Use a script argument per game, or derive
  it from `$Game.InstallDirectory`. `$StartedProcessId` comes from the library plugin's controller.
  For Steam, that is the first process seen in the install directory.
- **Filtering by tag:** `$Game.Tags.Name -contains 'UEVR'`. `Tags` is null for an untagged game;
  `-contains` on null returns false.
- **Extension instead?** A Playnite generic plugin's `OnGameStarted` gets the same event and the
  same `StartedProcessId`. It would only add a build artifact to maintain. The global script is
  enough, so no extension.

## Controller input and Link

- **Mapping:** UEVR hooks `XInputGetState` and presents the Touch controllers to the game as an
  XInput pad: sticks; grips → LB/RB; triggers → LT/RT; A/B/X/Y; left menu → Start, long press →
  Back. Oculus extra: right thumbrest plus left stick → D-pad. It can be rebound under Runtime when
  on OpenXR. Games that don't read XInput get nothing from it.
- **Aiming:** `VR_AimMethod` (game, head, or either controller) and roomscale options give 3DoF or
  6DoF motion controls in some games. Others need UObjectHook profiles.
- **Gamepad vs Touch:** UEVR zeroes real-gamepad input while the Touch controllers were used
  recently. `VR_MotionControlsInactivityTimer` defaults to 30 s, and "Controllers allowed" turns
  Touch input off. Issue #122 reports an Xbox pad not working over Link until this timeout passed
  (community comment).
- **Link focus:** `OpenXR::update_input()` returns early unless the session is
  `XR_SESSION_STATE_FOCUSED`. OpenXR defines VISIBLE as visible but "cannot receive XR input".
  With the Link desktop view (where Playnite runs) in front, UEVR gets no controller input. Close
  it after launching (Link behaviour inferred from the spec, unverified on the VM).
- **Window focus:** the frontend brings the game window to the front after injecting. In-game, the
  UEVR menu opens at startup by default. L3+R3 or Insert toggles it, and "Remember Menu Open/Closed
  State" keeps it closed in later sessions.

## Anti-cheat

UEVR docs, "To-dos before injection": "Double check that the game you are injecting into has no
Anti-Cheat mechanisms. If you are not sure, assume that all multiplayer games have Anti-Cheat, and
do not attempt to inject into them. The exception here is if it can be disabled in some way to play
offline." The spec's single-player rule matches. UEVR has no anti-cheat bypass. Third-party
"auto-inject for weaker anti-cheat" claims (Custom UEVR Injector) aren't a reason to relax it.

## Sources

- **UEVR:**
  - README (getting started, rendering modes, to-dos):
    <https://github.com/praydog/UEVR/blob/master/README.md>
  - Releases (1.05, 2024-11-16): <https://github.com/praydog/UEVR/releases/tag/1.05>
  - Nightlies: <https://github.com/praydog/UEVR-nightly/releases>
  - Release build (frontend from `praydog/uevr-frontend`, nightly zip contents):
    <https://github.com/praydog/UEVR/blob/master/.github/workflows/dev-release.yml>
  - UE 5.5/5.6 commits: <https://github.com/praydog/UEVR/commit/7e215b4>,
    <https://github.com/praydog/UEVR/commit/e3f053c>, <https://github.com/praydog/UEVR/commit/158232a>
  - Runtime choice in the backend (`initialize_openvr`, `initialize_openxr`, XInput emulation):
    <https://github.com/praydog/UEVR/blob/master/src/mods/VR.cpp>
  - Config keys: <https://github.com/praydog/UEVR/blob/master/src/mods/VR.hpp>,
    <https://github.com/praydog/UEVR/blob/master/src/mods/FrameworkConfig.hpp>
  - FOCUSED gate on input: <https://github.com/praydog/UEVR/blob/master/src/mods/vr/runtimes/OpenXR.cpp>
  - Profile directory (`get_persistent_dir`): <https://github.com/praydog/UEVR/blob/master/src/Framework.cpp>
  - XInput hook: <https://github.com/praydog/UEVR/blob/master/src/hooks/XInputHook.cpp>
  - Issues: <https://github.com/praydog/UEVR/issues/122>, <https://github.com/praydog/UEVR/issues/409>
- **UEVR frontend:**
  - `--attach`, auto-inject, settings, export/import:
    <https://github.com/praydog/UEVR-Frontend/blob/main/UEVR/MainWindow.xaml.cs>
  - Saved settings and defaults:
    <https://github.com/praydog/UEVR-Frontend/blob/main/UEVR/MainWindowSettings.cs>
  - LoadLibrary injection: <https://github.com/praydog/UEVR-Frontend/blob/main/UEVR/Injector.cs>
  - Zip import/export: <https://github.com/praydog/UEVR-Frontend/blob/main/UEVR/GameConfig.cs>
  - .NET 6 target: <https://github.com/praydog/UEVR-Frontend/blob/main/UEVR/UEVR.csproj>
  - Commits "Add --attach= command line arg for third party UEVR usage" and "Shutdown if attached
    game closes": <https://github.com/praydog/UEVR-Frontend/commit/0b18b49>,
    <https://github.com/praydog/UEVR-Frontend/commit/86c0d72>
- **UEVR docs:**
  - Introduction (anti-cheat, troubleshooting, Rai Pal): <https://praydog.github.io/uevr-docs/>
  - Detailed overview (OpenVR vs OpenXR, configurations, depth buffer):
    <https://praydog.github.io/uevr-docs/usage/overview.html>
  - Controller bindings: <https://praydog.github.io/uevr-docs/usage/vr_controller_bindings.html>
  - Website (UE 4.8–5.6, tested headsets): <https://uevr.io>
- **Khronos:**
  - OpenXR loader, active runtime and `XR_RUNTIME_JSON`:
    <https://registry.khronos.org/OpenXR/specs/1.1/loader.html#active-runtime-information>
  - Session states: <https://registry.khronos.org/OpenXR/specs/1.1/man/html/XrSessionState.html>
- **Meta:** setting Link as the active OpenXR runtime:
  <https://developers.meta.com/horizon/documentation/unreal/unreal-link/>
- **Playnite:**
  - Scripting overview (events, order, variables, synchronous, PowerShell 5.1):
    <https://api.playnite.link/docs/manual/features/scriptingSupport/scriptingSupportOverview.html>
  - Script execution and variables (`Controllers_Started`, `ExecuteScriptAction`):
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/GamesEditor.cs>
  - Runspace (bypass, `Stop`, current thread):
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Scripting/PowerShell/PowerShell.cs>
  - Labels ("Execute after a game is started", "Execute global script"):
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Localization/LocSource.xaml>
  - `Game` model (`Tags`, `InstallDirectory`, `UseGlobalGameStartedScript`):
    <https://github.com/JosefNemec/Playnite/blob/master/source/PlayniteSDK/Models/Game.cs>
  - Steam start detection (`StartedProcessId`):
    <https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/SteamLibrary/SteamGameController.cs>
  - Extension events: <https://api.playnite.link/docs/tutorials/extensions/events.html>
- **Third party (community, not UEVR's own):**
  - Rai Pal: <https://github.com/Raicuparta/rai-pal>; its UEVR definition:
    <https://github.com/Raicuparta/rai-pal-db/blob/main/scripts/mod-db/uevr/uevr-base.ts>
  - Chihuahua: <https://github.com/keton/chihuahua>
  - UEVR Easy Injector: <https://github.com/oduis/UEVRDeluxe> (delay:
    <https://github.com/oduis/UEVRDeluxe/blob/main/UEVRDeluxe/Code/AppUserSettings.cs>)
  - Custom UEVR Injector: <https://github.com/mirudo2/Custom-UEVR-Injector>
- **Unverified:**
  - Where the frontend's `user.config` lives, and whether an upgrade resets the OpenXR choice.
  - That the frontend stays running after the game exits (read from source, not observed).
  - Non-admin injection into a Playnite-launched Steam game.
  - The Oculus OpenXR manifest path.
  - Link desktop view leaving the session VISIBLE (inferred from the OpenXR spec).
  - Synchronized Sequential costing roughly a second render per tick (est.).
  - Profile compatibility across UEVR builds.
