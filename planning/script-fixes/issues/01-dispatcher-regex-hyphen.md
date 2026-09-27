# 01. Allow hyphens in the dispatcher/sudoers generators; regenerate secsvcs dispatcher

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 25

## Problem

`tools/gen_dispatch_cmds.sh:19,27` and `tools/parse_dispatcher.sh:33` match service names
with `[a-zA-Z0-9_]+`. `ntfy-alertmanager` exists in `src/secsvcs/install_svcs.sh` but is
absent from `src/secsvcs/dispatcher.sh` (both its own case and `install_all_svcs`), and
therefore from the generated sudoers.

## Change

- Change the character class to `[a-zA-Z0-9_-]+` in all three places.
- Re-run `tools/gen_dispatch_cmds.sh secsvcs` and paste the regenerated cases into
  `src/secsvcs/dispatcher.sh`, adding `install_ntfy-alertmanager` and inserting it into
  `install_all_svcs` after `install_alertmanager`.
- Add a one-line check to `tools/render_src.sh` (or the pre-commit hook, ci-and-docs/02):
  every `X)` case in `src/<node>/install_svcs.sh` must have an `install_X)` case in
  `src/<node>/dispatcher.sh`, for every node. Fail the render otherwise.

## Acceptance

- `ssh autoadmin@secsvcs install_ntfy-alertmanager` works after deploy; the render-time
  check passes for all nodes.

## Comments
