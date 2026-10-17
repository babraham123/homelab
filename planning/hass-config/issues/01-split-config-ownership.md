# 01. Repo-owned base config, UI-owned files, hand-written packages

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-14; design in [spec.md](../spec.md)

## Change

- `src/services/home_assistant/configuration.yaml.j2`: under `homeassistant:`, add
  `packages: !include_dir_named packages`.
- `src/nodes/homesvcs/install_svcs.sh`, `home_assistant)` case: replace the
  "Have you manually updated" prompt.
  - Print a diff of each repo-owned file against the live one.
  - Back up the live repo-owned files to a temp dir, then install the repo's:
    - `configuration.yaml` and `mqtt.yaml` into the volume root;
    - `commands.yaml` into `custom_sentences/en/`. Today it lands in the root, where HA never reads
      it, which is a bug.
  - Install `automations.yaml`, `scripts.yaml`, `scenes.yaml` and `groups.yaml` only when missing.
  - `mkdir -p packages`.
  - Check the config, then `reload_restart home_assistant`. If the check fails, restore the temp
    copies and `die`. The check depends on whether HA is running:
    - running: `podman exec home_assistant python -m homeassistant --script check_config -c /config`;
    - not running (first install): a one-off `podman run --rm` of the same image with the volume
      mounted.
- `src/services/home_assistant/*.yaml`: fix the header comments. They say
  `/etc/opt/home_assistant/config/`, but the files live in the `hassconfig` volume.
- `docs/guides/homesvcs.md.j2`, a short "Config files" section:
  - the ownership table from the spec;
  - how to add a package over SSH, with the volume path from `podman volume inspect`;
  - that changes to repo-owned files go through the repo and a reinstall.
- `notes/apply-since-<sha>.md`, in the main checkout (gitignored, so a worktree has no copy; edit
  it there):
  - add a "What changes" row: config ownership split, `packages/`, the `commands.yaml` path, and
    the config check before restart;
  - in the homesvcs step, add the "Before the first run" reconcile, then
    `ssh autoadmin@homesvcs install_home_assistant` (no prompt now), then this ticket's acceptance
    checks.

## Before the first run

The live `configuration.yaml` may have hand edits the repo doesn't have. Before installing:

1. Diff the live file against `rendered/`.
2. Move each live-only block into the repo or into a `packages/` file.

The first run then reports no unexpected diff.

## Acceptance

- Reinstalling with no repo changes prints empty diffs, restarts HA, and leaves the UI-owned files
  and `packages/` unchanged.
- A package file in `packages/`, for example a template sensor, shows up after the restart and
  survives a reinstall.
- An automation made in the UI survives a reinstall.
- A deliberately broken `configuration.yaml.j2` makes install stop with the check's error. The live
  files are unchanged and HA keeps running.
- The conversation agent recognises a sentence from `commands.yaml`, once there is one.

## Comments
