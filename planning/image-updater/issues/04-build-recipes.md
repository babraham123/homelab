# 04. Move build recipes into build.sh; updater builds on websvcs

Status: resolved Type: task Repo: homelab Source: notes/image-updater-design.md "Built images
(websvcs only)" Blocked by: 03

## Change

- Move each `podman build` recipe out of `src/nodes/websvcs/install_svcs.sh` (`novnc`,
  `finance_exporter`, `piper`, `whisper`, `openwakeword`) into `src/services/<service>/build.sh`,
  called by both `install_svcs.sh` and the updater. Each prints the release versions it resolved.
  Built images keep single-segment names (`localhost/piper:latest`).
- Updater: for piper, whisper and openwakeword, check GitHub releases nightly; on a version change
  build to `:candidate`, `podman save` + `trivy --input`, then old → `:rollback`, `:candidate` →
  `:latest`. The wyoming context stays on `wyoming-addons` branch HEAD.
- `src/nodes/websvcs/commands.sh build_novnc` / `build_finance_exporter` (no parameters), added to
  the websvcs dispatcher.

## Acceptance

- `install_svcs.sh piper` on a fresh websvcs produces the same image as today.
- A faked version bump builds, scans and swaps tags; a failed scan leaves `:latest` untouched.

## Answer

Scope cut on 2026-10-11: all five recipes are commented out on websvcs (not in use), so only the
updater's build path is done. The recipes stay commented, and there are no `build_novnc` or
`build_finance_exporter` commands.

- `check_build` in the updater: `src/services/<service>/build.sh versions` prints the release
  versions; when they change, `build.sh build candidate`, `podman save` + Trivy, then the old image
  goes to `:rollback` and the new one to `:latest`. The candidate is untagged before the gate, so a
  blocked build leaves `:latest` untouched and only a dangling image the prune removes.
- Images with no `build.sh` (today `geoip_generator` on vpnsvcs) are reported "built by hand" and
  rebuilt by installing them again. `accept` refuses built images; `.trivyignore` still applies.
- Re-enabling a recipe: move it to `build.sh` (`versions`, `build TAG`), add `build: <name>` to the
  inventory, and the install-time gate builds it.

## Comments
