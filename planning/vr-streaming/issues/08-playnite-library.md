# 08. Playnite library: EA app games and Dolphin/Eden, playable with a controller only

Status: ready-for-human Type: task Repo: homelab Source: maintainer request 2026-10-16; research in
[playnite-research.md](../playnite-research.md)

Playnite is the front end in flat, UEVR and direct mode, but two parts of its library don't work
from the couch:

- EA app games launch, then Playnite decides they stopped, runs the post-game script and comes back
  over the game. The plugin that imports them, Josef's Origin plugin, has been deleted.
- The gaming guide sets up yuzu and Ryujinx, both shut down, with keys from a download site, and
  launches nothing fullscreen. Playnite has no close-game control, so a game with no exit combo
  traps the controller.

## Decisions

- **Jeshibu's "EA app library integration" (3.2.2 or later) imports EA games.** It's the addon
  database's only EA library and keeps the old addon ID, so it updates the old plugin in place.
- **A game that falsely stops gets its own play action, not a `Start-Sleep` script.** Type URL
  `origin2://game/launch/?offerIds=<contentId>`, Tracking mode Process name set to the real exe
  (no `.exe`, case-sensitive), Initial tracking delay 30000–60000 ms, and "Include library
  integration play actions" unticked. This waits for the real game without blocking Playnite, and
  06's "After game started" script gets the game's PID, not a launcher stub's. Only games that show
  the problem get one.
- **Dolphin for GameCube/Wii, Eden for Switch,** on Playnite's built-in profiles. Playnite's own
  Switch download list is `[eden, sudachi]`; Sudachi has stalled. Ryubing is the fallback and needs
  no custom profile: Playnite's Ryujinx profile matches its `Ryujinx.exe`.
- **Every emulator launches fullscreen and exits on a controller combo without Guide.** tvOS may
  keep the Guide button for itself (unverified), and Eden's default exit uses Home (Guide).
  Exit combos: Dolphin Stop on `` `Back` & `Start` ``, which quits it in batch mode; Eden Exit on
  L+Plus+Minus. Now Playing is the fallback for a hung game.
- **Keys and firmware come from an owned Switch,** dumped with Lockpick_RCM.
- **Configured by hand, recorded in the guide.** Playnite keeps its settings in its own database;
  nothing here is templated.

## Change

On the VM, over Moonlight (the console session), with a keyboard and mouse for setup:

- Playnite updated to 10.62 or later (Process name tracking needs 10.36, the Eden profile is
  newer).
- EA:
  - Add-ons → install "EA app library integration"; sign in to EA; update the library.
  - Launch each installed EA game from Playnite fullscreen. For each one that comes back to
    Playnite while it's still running, add the play action above. The contentId comes from the
    plugin's `Starting EA content <id>` log line or `contentID` in
    `<game>\__Installer\installerdata.xml`; the exe name from Task Manager.
- Emulators:
  - Uninstall yuzu and Ryujinx and remove their Playnite emulator entries and games.
  - Install Dolphin (2609a or later) and Eden (v0.2.1 or later, Windows amd64 msvc zip); Library →
    Configure emulators → Import.
  - Dolphin's GameCube and Wii profiles: Override default args,
    `--batch --exec="{ImagePath}" -C Dolphin.Display.Fullscreen=True -C Dolphin.Interface.ConfirmStop=False`.
  - Dolphin: map Standard Controller to the XInput pad; bind Stop as above.
  - Eden: install the dumped keys and firmware; map Player 1 to the Xbox pad; rebind Exit.
  - One auto-scan configuration per ROM folder, then Update emulated folders. Switch games match
    metadata by file name, so name them by title.
- Install Now Playing; check the fullscreen theme shows its button.
- If Guide doesn't reach the VM from the Apple TV, set Sunshine's `back_button_timeout = 2000` so
  holding Back sends Guide.
- `docs/guides/gaming.md`, Streaming section:
  - replace the Yuzu/Ryujinx/keys and Dolphin bullets with Dolphin and Eden: install, Import,
    Dolphin's arguments, both exit combos, keys and firmware from an owned Switch, auto-scan;
  - add EA: the plugin, and how to give a falsely stopping game its own play action;
  - Now Playing, and `back_button_timeout` if it was needed.

## Acceptance

All over Moonlight on the Apple TV, with only the Xbox controller:

- An EA game that falsely stopped before launches from Playnite fullscreen, and Playnite stays in
  the background until the game is quit. Its playtime records the session.
- A GameCube and a Wii game launch fullscreen from Playnite, with GameCube/Wii metadata, and the
  exit combo returns to Playnite with no dialog.
- A Switch game launches fullscreen in Eden, and its exit combo returns to Playnite.
- Now Playing closes a running emulator from Playnite.
- The guide has no yuzu, Ryujinx or key download steps.

## Comments
