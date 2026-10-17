# 05. Fix the local preview instructions

Status: resolved
Type: task
Repo: homesite
Source: review finding 43

In `setup.md`, replace

```bash
open assets/www/index.html
```

with

```bash
cd src/www && mkdocs serve
```

and note that the built `assets/` tree only renders correctly when served at the configured
`site_url` root (absolute paths, search index).

## Comments

- 2026-10-17: verified done in the homesite repo: `setup.md` previews with `tools/mkdocs.sh serve`
  (the pinned mkdocs, run in `src/www`) and warns that the built `assets/` tree only renders when
  served at the `site_url` root.
