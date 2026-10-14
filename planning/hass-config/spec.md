# Home Assistant config ownership

Split Home Assistant's `/config` by owner, the same way as ESPHome
([esphome/spec.md](../esphome/spec.md)):

- the repo owns the base config, and install overwrites it every time;
- the UI owns what it writes;
- hand-written YAML goes in `packages/`, which install never touches.

Maintainer request 2026-10-14.

Today the `home_assistant)` case in `src/nodes/homesvcs/install_svcs.sh` copies every repo YAML only
on first install. After that it asks "Have you manually updated the config files?", so the live
`configuration.yaml` drifts from the repo with nothing to show it.

## Ownership

| Path in `/config` | Owner | Install |
| --- | --- | --- |
| `configuration.yaml`, `mqtt.yaml`, `custom_sentences/en/commands.yaml` | repo | overwrite every time |
| `automations.yaml`, `scripts.yaml`, `scenes.yaml`, `groups.yaml` | HA's UI editors | create if missing |
| `packages/*.yaml` | maintainer, by hand | never touched; the directory is created |
| `.storage/`, `custom_components/`, `backups/` | HA | never touched |

## Decisions

- **Packages for hand-written YAML.** `configuration.yaml.j2` gets
  `packages: !include_dir_named packages` under `homeassistant:`. Each file in `/config/packages/`
  is one package, and HA merges its top-level integration keys into the config. Automations in a
  package are read-only in the UI, which is the point.
- **Check before restart.** Install puts the new repo files in place, then runs HA's
  `check_config` in the container. If the check fails, install puts the old files back and stops
  without restarting, so a bad template can't drop HA into recovery mode.
- **No editor in the browser.** The File editor and Studio Code Server are add-ons, and add-ons
  exist only on HA OS, not in the container. `packages/` is edited over SSH on homesvcs.
- **Backups don't change.** HA's native backup, which `backup.sh` already takes weekly, includes all
  of `/config`, packages too.

## Issues

| # | Title | Status | Type |
| --- | --- | --- | --- |
| [01](issues/01-split-config-ownership.md) | Repo-owned base config, UI-owned files, hand-written packages | `ready-for-agent` | task |
