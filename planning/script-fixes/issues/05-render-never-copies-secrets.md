# 05. render_src.sh: never copy vars.yml or .git into the rendered tree

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 29 (maintainer: implement the best fix)

## Problem

`tools/render_src.sh` does `cp -R . "$project_dir"` (copies `.git`, `vars.yml`,
`planning/`, `notes`) and then deletes some of them, so `vars.yml` briefly exists under
`/tmp/homelab-rendered`, a fixed, world-traversable path.

## Best fix

`git archive` would be cleanest but excludes uncommitted edits, which breaks the
render-while-developing loop. Use rsync with an explicit exclude list and a private temp
dir:

```bash
project_dir=${1:-"$(mktemp -d)/homelab-rendered"}
mkdir -p "$project_dir"
rsync -a --delete   --exclude .git --exclude .gitignore --exclude .vscode --exclude .fdignore   --exclude planning --exclude notes --exclude vars.yml --exclude all_vars.yml   --exclude '.DS_Store' ./ "$project_dir/"
```

`mktemp -d` gives a `0700` directory; `deploy_src.sh` should stop passing the fixed
`/tmp/homelab-rendered` and use the returned path (the *name* `homelab-rendered` must be
kept because `upload_src.sh` moves it to `/root/homelab-rendered` by name). Also write
`all_vars.yml` into that temp dir rather than the repo root.

## Acceptance

- `find /tmp -name vars.yml` is empty during and after a render.
- `git status` is clean after a render (no stray `all_vars.yml`).

## Comments
