# 02. Comment the intentional mv of rendered files in install_svcs.sh

Status: wontfix
Type: task
Repo: homelab
Source: review finding 26 (maintainer: mv is intentional, add a comment)

## Change

At each `mv` of a rendered file — `src/nodes/secsvcs/install_svcs.sh:114`,
`src/nodes/homesvcs/install_svcs.sh:27,74`, `src/nodes/websvcs/install_svcs.sh:33,142` — add:

```bash
# mv, not cp: render_host.sh rendered this file in place inside /root/homelab-rendered,
# which is recreated on every upload. Re-running this case without a fresh upload will
# fail on purpose rather than install a stale render.
```

Also document the rule in `docs/development.md#service-structure`: "files produced by a second
render on the node are consumed with `mv`; the rendered tree is disposable".

## Comments

- 2026-10-10: Superseded. ce1d9f8 replaced every `mv` out of the rendered tree with `install -D`, so
  install_svcs.sh no longer consumes rendered files, and `render_host.sh` deletes and re-renders its
  output, so re-running a case without a fresh upload is safe. Nothing to comment.
