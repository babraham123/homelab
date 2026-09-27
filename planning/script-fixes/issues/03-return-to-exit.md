# 03. Replace top-level `return` with `exit 1` in upload scripts

Status: ready-for-agent
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

## Comments
