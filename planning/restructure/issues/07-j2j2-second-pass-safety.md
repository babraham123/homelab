# 07. Guard the .j2.j2 second-pass templates

Status: wontfix
Type: task
Repo: homelab
Source: review structure note (maintainer: don't worry about this for now)

Maintainer decision: leave the `{% raw %}` convention as is. Revisit if a second-pass
variable is ever silently rendered empty.

## Comments

- 2026-10-30: moot. The second pass now uses its own delimiters, `[[ ]]` and `[% %]`
  (`src/base/podman/second_pass.py`), so no `{% raw %}` remains and neither pass can render the
  other's variables. The host pass is gone too: a shared quadlet's per-node lines are the node's
  drop-in, `src/nodes/<node>/<quadlet>.container.d/`.
