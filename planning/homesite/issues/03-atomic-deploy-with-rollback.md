# 03. Release-directory deploy with a bounded rollback history

Status: ready-for-agent
Type: task
Repo: homesite
Source: review finding 41

## Problem

`tools/deploy_src.sh` does `sudo rm -rf /var/opt/nginx/www/*` then `cp -r`; an
interrupted copy leaves the public site broken with nothing to roll back to.

## Change

- Upload to `/var/opt/nginx/releases/<UTC timestamp>/`, then atomically
  `ln -sfn releases/<ts> /var/opt/nginx/www.new && mv -T /var/opt/nginx/www.new /var/opt/nginx/www`
  (symlink swap is atomic; `mv -T` replaces the link). Keep the last **3** releases,
  delete older.
- `tools/rollback.sh` that points `www` at the previous release.
- **Cross-repo touch:** `homelab/src/nginx/nginx.container.j2:23` mounts
  `/var/opt/nginx/www:/www:ro`. A symlink *inside* a bind mount resolves on the host side
  only if the target is also visible in the container. Change the mount to
  `Volume=/var/opt/nginx:/srv:ro` and set nginx `root /srv/www/...` in
  `homelab/src/nginx/nginx.conf.j2`, so the symlink and its targets are both inside the
  mount. Redeploy nginx once.

## Acceptance

- Deploy, then `rollback.sh`, then deploy again; site serves throughout; only 3
  directories under `releases/`.

## Comments
