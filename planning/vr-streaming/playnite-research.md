# Playnite: EA app games and emulators: research

Research for the gaming VM's Playnite (flat mode over Sunshine, 06's UEVR mode, 07's direct mode),
2026-10-16. Primary sources first. Community reports are marked (community); claims no source
confirms are marked (unverified).

## Recommendation

1. **Replace the EA plugin with Jeshibu's "EA app library integration" (3.2.2).** Josef's Origin
   plugin broke when EA's Origin APIs went away and was deleted on 2025-10-15. Jeshibu's rebuild
   keeps the addon ID `OriginLibrary_Builtin`, so an existing install updates in place
   ([EA app games](#ea-app-games)).
2. **Fix a falsely "stopped" EA game with its own play action, not `Start-Sleep`.** Type URL
   `origin2://game/launch/?offerIds=<contentId>`, Tracking mode **Process name** set to the real
   exe (no `.exe`, case-sensitive), Initial tracking delay 30000–60000 ms, and "Include library
   integration play actions" unticked. Playnite stays responsive, and "After game started" fires
   with the real game's `$StartedProcessId`, which 06's `uevr_inject.ps1` depends on
   ([Fix](#fix-a-custom-play-action)).
3. **Use Dolphin for GameCube/Wii and Eden for Switch.** yuzu and suyu are dead, Ryujinx lives on
   as Ryubing, and Playnite's own Switch download list is `[eden, sudachi]`. Playnite 10.62 ships
   built-in profiles for both ([Emulators](#emulators)).
4. **Launch both fullscreen and bind an exit combo in each emulator.** Playnite has no "close game"
   control, and the Guide button may not reach the VM through the Apple TV
   ([Controller-only play](#controller-only-play)).
5. **Dump keys and firmware from an owned Switch** with Lockpick_RCM. The gaming guide's
   theprodkeys.com step should go.

## EA app games

### Plugin status

- **Removal:** the Origin plugin called Origin APIs, which started returning 403 and then 404
  around EA's April 2025 Origin shutdown. Josef stopped maintaining it and offered its addon ID to a
  fork ([#448](https://github.com/JosefNemec/PlayniteExtensions/issues/448)). He closed #448 and
  deleted the code in
  [f61dfdcf](https://github.com/JosefNemec/PlayniteExtensions/commit/f61dfdcf) on 2025-10-15.
- **Successor:** [Jeshibu_EaLibrary.yaml](https://github.com/JosefNemec/PlayniteAddonDatabase/blob/master/addons/library/Jeshibu_EaLibrary.yaml)
  is the addon database's only EA library entry. The Codeberg fork
  ([CrowIsTaken/PlayniteExtensions](https://codeberg.org/CrowIsTaken/PlayniteExtensions)) has no
  EA plugin.
- **Releases** ([manifest](https://github.com/Jeshibu/PlayniteExtensions/blob/main/manifests/Library_EA.yaml)):

  | Version | Date | Change |
  | --- | --- | --- |
  | 3.0 | 2025-10-12 | Rebuilt on EA's new backend; import needs an EA sign-in |
  | 3.2 | 2025-11-01 | Imports playtime and last played |
  | 3.2.1 | 2026-04-15 | Fixed broken game import |
  | 3.2.2 | 2026-06-25 | Fixed broken game import |

  Import has broken twice in a year on EA backend changes.
- **What it does** ([source](https://github.com/Jeshibu/PlayniteExtensions/tree/main/source/EaLibrary)):
  - imports owned games, optionally uninstalled ones;
  - reads install state from the registry path in each offer's `installCheckOverride`;
  - installs and uninstalls through the EA app;
  - launches `origin2://game/launch/?offerIds=<contentId>`.

### Why games look stopped

- **Issue [#384](https://github.com/JosefNemec/PlayniteExtensions/issues/384)** (closed
  2024-07): EA games launch, but Playnite decides they stopped after a few seconds, runs the
  post-game script and comes back to the foreground. Josef raised the old plugin's timings in 2.13
  and won't do per-game tracking. The thread's workaround, a per-game `Start-Sleep 120` before the
  game starts, blocks Playnite.
- **Old plugin:** after an EA app or EAC launch, it slept 40 s, then watched the install folder
  ([OriginGameController.cs](https://github.com/JosefNemec/PlayniteExtensions/blob/d59a97d5/source/Libraries/OriginLibrary/OriginGameController.cs)).
- **Jeshibu's plugin**
  ([ProcessMonitor.cs](https://github.com/Jeshibu/PlayniteExtensions/blob/main/source/EaLibrary/Shared/ProcessMonitor.cs)):
  - watches the install folder, polling every 2 s, or every 40 s when an `EasyAntiCheat*.dll` is
    there. Its `trackingDelay` is the poll interval, not an initial delay;
  - the first process seen in the folder is "started" and supplies `StartedProcessId`;
  - the first poll that finds none is "stopped".
- **Effect:** when a launcher stub or EAC bootstrapper exits before the real exe starts, Playnite
  records a stop, and `StartedProcessId` can be the stub's PID. The launch chain (EA app → stub or
  `start_protected_game` → relaunch → real exe) is inferred from the old plugin's 40 s wait
  (unverified).

### Playnite's tracking fields

`GameAction` ([GameAction.cs](https://github.com/JosefNemec/Playnite/blob/master/source/PlayniteSDK/Models/GameAction.cs),
[manual](https://api.playnite.link/docs/manual/library/games/gameActions.html)):

| Field | Values / default | Since |
| --- | --- | --- |
| `TrackingMode` | Default, Process, Directory (UI "Folder"), OriginalProcess, ProcessName | ProcessName in [10.36](https://github.com/JosefNemec/Playnite/releases/tag/10.36) (2025-06-12) |
| `TrackingPath` | folder, or process name | |
| `InitialTrackingDelay` | ms, default 0 | [10.30](https://github.com/JosefNemec/Playnite/releases/tag/10.30) (2023-12-13) |
| `TrackingFrequency` | ms, default 2000 | 10.30 |

- **Folder and Process name modes**
  ([GenericGameController.cs](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Controllers/GenericGameController.cs)):
  wait `InitialTrackingDelay`, poll with no time limit until a match exists, then fire OnStarted
  with that PID. The stub phase is skipped as long as the delay covers it.
- **Matching**
  ([ProcessMonitor.cs](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Common/ProcessMonitor.cs)):
  Process name compares `Process.ProcessName` exactly, with no `.exe` and case-sensitive.
  Process and OriginalProcess modes need a process handle, which a URL launch likely doesn't give
  (unverified).
- **Scripts:** "After game started" gets `$StartedProcessId` from OnStarted
  ([GamesEditor.cs](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/GamesEditor.cs)).

### Fix: a custom play action

Edit game → Actions, ranked:

1. **URL action, Process name tracking.**
   - Path `origin2://game/launch/?offerIds=<contentId>`.
   - Tracking path: the real exe name; for UE games usually `<Game>-Win64-Shipping`.
   - Initial tracking delay 30000–60000, frequency 2000.
   - Untick "Include library integration play actions", or Playnite shows a picker, fullscreen
     included.
   - If the stub has the same name as the real exe, the delay must cover the hand-off.
2. **Same action, Folder tracking** on the binaries folder (e.g. `Binaries\Win64`) rather than the
   install root, for a game whose exe name varies.
3. **Plugin default** for games that don't relaunch themselves. Whether a library update
   overwrites custom actions is unverified.
4. **EA games bought on Steam** still go through the EA app (community:
   [CachyOS forum](https://discuss.cachyos.org/t/proper-way-of-installing-and-running-ea-games-very-low-performance-compared-to-windows/22063)),
   and the Steam plugin watches the folder the same way
   ([SteamGameController.cs](https://codeberg.org/CrowIsTaken/PlayniteExtensions/src/branch/main10/source/Libraries/SteamLibrary/SteamGameController.cs)).
   Same fix, with `steam://rungameid/<appid>`.
5. **Script play action:** OnStarted fires at once with no PID, and the game stops when the script
   returns. The script would have to wait for the game and inject UEVR itself.
6. **`Start-Sleep` before the game starts:** blocks Playnite. Worst.

### EA gotchas

- **contentId:**
  - launch once through the plugin, which logs `Starting EA content <id>`
    ([EaControllerHelper.cs](https://github.com/Jeshibu/PlayniteExtensions/blob/main/source/EaLibrary/ActionControllers/EaControllerHelper.cs));
    which Playnite log it lands in is unverified;
  - or `contentID` in `<game>\__Installer\installerdata.xml` (community:
    [EA forums](https://forums.ea.com/discussions/ea-play-general-discussion-en/launch-ea-game-using-command/7575680),
    where an ID from `ProgramData\EA Desktop\InstallData` failed for one game).
- **EA app:** must be installed; the plugin finds it through the `OriginPath` / `ClientPath`
  registry values ([EaApp.cs](https://github.com/Jeshibu/PlayniteExtensions/blob/main/source/EaLibrary/EaApp.cs)).
- **Offline mode:** needs a recent online login; users report it drops after a few hours
  (community: [EA forums](https://forums.ea.com/kb/ea-app-tutorials-and-guides-en/infoguidehow-to-put-the-ea-app-in-offline-mode/11897237)).
- **Unverified:** whether EA app login or update windows cover Playnite fullscreen over Sunshine;
  whether the EA overlay conflicts with UEVR; whether the EA app needs admin.

## Emulators

### Playnite's emulation support

Playnite 10.62 (2026-09-29); 10.61 the same day updated emulation profiles
([releases](https://github.com/JosefNemec/Playnite/releases)).

- **Adding emulators:** Library → Configure emulators → **Import** scans a folder and matches
  executables against the built-in definitions; or Add, pick a specification, then a built-in or
  custom profile ([manual](https://api.playnite.link/docs/manual/features/emulationSupport/addingNewEmulators.html)).
- **Built-in profiles** take "Override default args", "Custom arguments" and pre/post/exit
  scripts ([Emulator.cs](https://github.com/JosefNemec/Playnite/blob/master/source/PlayniteSDK/Models/Emulator.cs)).
  Custom profiles set the executable, arguments (`{ImagePath}`, `{EmulatorDir}`), working folder,
  file types, tracking mode and a startup script.
- **Adding games**
  ([manual](https://api.playnite.link/docs/manual/features/emulationSupport/addingEmulatedGames.html)):
  - Auto-scan configurations: a folder → emulator + profile. Scans run from Update game library →
    Update emulated folders, on every library update if enabled, or once via Add game → Emulated
    game;
  - games are identified by checksum against a libretro-based database, with exclusions and
    multi-disc grouping;
  - GameCube and Wii have database entries; Switch doesn't, so Switch games match by file name
    ([Platforms.yaml](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Emulation/Platforms.yaml)).

### Built-in definitions

From [Emulation/Emulators](https://github.com/JosefNemec/Playnite/tree/master/source/Playnite/Emulation/Emulators):

| Emulator | Status (2026-10) | Executable | Built-in args | Extensions |
| --- | --- | --- | --- | --- |
| Dolphin | Active; 2609a (2026-10-08) ([tags](https://github.com/dolphin-emu/dolphin/tags)) | `Dolphin.exe` | `--exec="{ImagePath}" --batch` | GC: elf, dol, gcm, tgc, ciso, gcz, iso, wad, dff, rvz, m3u; Wii adds wbfs, wia |
| Eden | Active; v0.2.1 (2026-06-01) ([releases](https://git.eden-emu.dev/eden-emu/eden/releases)) | `eden.exe` | `-f -g "{ImagePath}"` | nso, nro, nca, xci, nsp |
| Ryujinx | Upstream shut down 2024-10; Ryubing continues it | `ryujinx.exe`, `ryujinx.ava.exe` | `--fullscreen "{ImagePath}"` | xci, nsp |
| Citron | Original stalled; [Citron Neo](https://github.com/citron-neo/emulator/releases) has 2026 nightlies | | `"{ImagePath}"` (windowed; override to `-f -g "{ImagePath}"`, per [main.cpp](https://github.com/citron-neo/emulator/blob/HEAD/src/citron/main.cpp)) | nso, nro, nca, xci, nsp |
| Sudachi | Stalled since ~2025-07 (community, unverified) | | `"{ImagePath}"` | nso, nro, nca, xci, nsp |
| yuzu, suyu | Dead; suyu [DMCA-blocked](https://github.com/github/dmca/blob/master/2024/07/2024-07-05-nintendo.md) | | | |

- **Ryubing has no definition of its own, and needs none.** The Ryujinx definition's `Default`
  profile matches `^ryujinx\.exe$`, case-insensitively
  ([Scanner.cs](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Emulators/Scanner.cs)),
  and Ryubing's `Ryujinx.csproj` sets no `AssemblyName`, so it builds `Ryujinx.exe`
  ([mirror](https://github.com/Leuconoe/Ryubing/blob/HEAD/src/Ryujinx/Ryujinx.csproj); the official
  git.ryujinx.app wasn't reachable). The fullscreen argument was added 2026-05-04
  ([#4310](https://github.com/JosefNemec/Playnite/pull/4310)). Ryubing's latest releases (stable
  1.3.3, canary 1.3.351) are from search results only (unverified).
- **Playnite's Switch download list** is `[eden, sudachi]`; its comment calls Suyu and Citron "not
  recommended… due to inactivity (Suyu)/shady behavior (Citron)"
  ([Platforms.yaml](https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Emulation/Platforms.yaml)).
- **Eden:** `-f, --fullscreen`, `-g, --game`. Given a path without `-f`, it forces windowed
  ([launch_params.cpp](https://git.eden-emu.dev/eden-emu/eden/src/branch/master/src/core/launch_params.cpp),
  [main_window.cpp](https://git.eden-emu.dev/eden-emu/eden/src/branch/master/src/yuzu/main_window.cpp)).
- **Dolphin:** `-b/--batch`, `-e/--exec`, and `-C Dolphin.<Section>.<Key>=<Value>`. Relevant keys:
  `Dolphin.Display.Fullscreen` (default False) and `Dolphin.Interface.ConfirmStop` (default True).
  In batch mode, stopping emulation quits Dolphin
  ([CommandLineParse.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp),
  [MainSettings.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/MainSettings.cpp),
  [MainWindow.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/MainWindow.cpp)).

### Controller-only play

- **No close-game control in Playnite.** Guide-button options only focus Playnite or switch to
  fullscreen; 10.61 added "Only focus if no game is running"
  ([commit](https://github.com/JosefNemec/Playnite/commit/e6745eb8)). Button rebinding is slated
  for Playnite 11 ([manual](https://api.playnite.link/docs/manual/gettingStarted/playniteFullscreenMode.html)).
- **Guide over the Apple TV:** tvOS may keep the Guide button for itself (community, unverified:
  [LaunchBox forum](https://forums.launchbox-app.com/topic/77276-tutorial-xbox-one-controller-apple-tv-moonlight-sunshine-big-box)).
  Sunshine's `back_button_timeout` (e.g. `2000`) turns a long Back hold into Guide
  ([Sunshine config](https://github.com/LizardByte/Sunshine/blob/master/docs/configuration.md)).
- **What the VM sees:** with `gamepad_driver=vigembus`, an Xbox 360 or DS4 pad. ViGEmBus is
  end-of-life (same doc).
- **Dolphin:** hotkeys include Stop and Exit, and bindings take `&` expressions, e.g.
  `` `Back` & `Start` ``
  ([HotkeyManager.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/HotkeyManager.cpp),
  [ExpressionParser.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/InputCommon/ControlReference/ExpressionParser.cpp)).
- **Eden:** default controller hotkeys are Exit = Home+Minus, Stop = L+Plus+Minus, Fullscreen =
  Home+B ([uisettings.cpp](https://git.eden-emu.dev/eden-emu/eden/src/branch/master/src/qt_common/config/uisettings.cpp)).
  Home is Guide, so rebind exit to a combo without it.
- **Fallback:** [Now Playing](https://github.com/jonosellier/NowPlaying) (v0.6.1, 2026-05-06)
  closes the running game from Playnite, if the fullscreen theme shows its button.

### Library and metadata addons

- **[EmuLibrary](https://github.com/psychonic/Playnite-EmuLibrary)** (v3.9.1, 2026-08-07): ROMs on
  an SMB share, "installed" to a local path. Its Yuzu ROM type supports Eden and Citron Neo and
  installs games, updates and DLC into the emulator's NAND.
- **[LaunchBox Metadata](https://github.com/Jeshibu/PlayniteExtensions)** (2026-04-11).
- **[RomM Library Importer](https://github.com/rommapp/playnite-plugin)** 0.9.0 (2026-09-16).
- **[ScreenScraper](https://github.com/polson/screenscraper-playnite-metadata-plugin)**: last
  release 2022, stale.

### Keys and firmware

Dump `prod.keys`, `title.keys` and firmware from an owned Switch with Lockpick_RCM through Hekate
([Ryubing docs](https://github.com/Ryubing/docs/blob/HEAD/docs/guides/dumping/keys.md)).

### Setup

**Dolphin:**

1. Install Dolphin 2609a; Configure emulators → Import its folder, which picks up the GameCube and
   Wii profiles.
2. In both profiles, tick Override default args and set
   `--batch --exec="{ImagePath}" -C Dolphin.Display.Fullscreen=True -C Dolphin.Interface.ConfirmStop=False`.
3. In Dolphin: map Standard Controller to the XInput pad; bind the Stop hotkey to
   `` `Back` & `Start` ``.
4. Add an auto-scan configuration for the ROM folder, then Update emulated folders.
5. Over Moonlight, check the controller exits back to Playnite.

**Eden:**

1. Download the v0.2.1 Windows amd64 msvc zip; Import its folder. The built-in profile already
   passes `-f -g "{ImagePath}"`.
2. Install the dumped keys and firmware in Eden (menu path unverified).
3. Map Player 1 to the Xbox pad; rebind Exit to a combo without Home.
4. Add games by an auto-scan of the `.xci`/`.nsp` folder, or EmuLibrary's Yuzu type on a share.
