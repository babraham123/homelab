# 03. Replace top-level `return` with `exit 1` in upload scripts

Status: resolved
Type: task
Repo: homelab
Source: review finding 27 (maintainer asked to check whether set -e makes it intentional)

## Investigation result

Tested: under `set -euo pipefail`, a top-level `return` in a non-sourced script prints
`return: can only 'return' from a function or sourced script` and the shell exits with
status 1 because the failed builtin trips `set -e`. So the *behaviour* is what was wanted
(abort when the host is unreachable), but it relies on an error path and prints a
misleading message. Not intentional in the sense of correct; harmless in effect.

## Change

- `tools/upload_src.sh:15` → `exit 1`.
- `homesite/tools/deploy_src.sh:18` → `exit 1`.
- shellcheck (SC2317/SC2168 family) flags this; enabling it in the pre-commit hook
  (ci-and-docs/02) prevents recurrence.

## Answer

- `tools/upload_src.sh`: the unreachable-host branch now ends with `exit 1`, so the
  script fails with only the `error: <host> is not reachable` message.
- `tools/deploy_src.sh` in this repo has no top-level `return` and needed no change.
  `homesite/tools/deploy_src.sh` is in the homesite repo, so it is out of scope here.
  Each `upload_src.sh` call in `deploy_src.sh` still ends in `|| echo "<host> upload failed"`,
  so the deploy carries on past an unreachable host and exits 0, which is what 04 (wontfix) wants.

## Comments
