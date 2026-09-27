# 04. Move build recipes into build.sh; updater builds on websvcs

Status: ready-for-agent
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Built images (websvcs only)"
Blocked by: 03

## Change

- Move each `podman build` recipe out of `src/websvcs/install_svcs.sh` (`novnc`,
  `finance_exporter`, `piper`, `whisper`, `openwakeword`) into `src/<service>/build.sh`,
  called by both `install_svcs.sh` and the updater. Each prints the release versions it
  resolved. Built images keep single-segment names (`localhost/piper:latest`).
- Updater: for piper, whisper and openwakeword, check GitHub releases nightly; on a
  version change build to `:candidate`, `podman save` + `trivy --input`, then old →
  `:rollback`, `:candidate` → `:latest`. The wyoming context stays on `wyoming-addons`
  branch HEAD.
- `src/websvcs/commands.sh build_novnc` / `build_finance_exporter` (no parameters),
  added to the websvcs dispatcher.

## Acceptance

- `install_svcs.sh piper` on a fresh websvcs produces the same image as today.
- A faked version bump builds, scans and swaps tags; a failed scan leaves `:latest`
  untouched.

## Comments
