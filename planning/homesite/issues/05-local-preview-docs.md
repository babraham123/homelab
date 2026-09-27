# 05. Fix the local preview instructions

Status: ready-for-agent
Type: task
Repo: homesite
Source: review finding 43

In `setup.md`, replace

```
open assets/www/index.html
```

with

```bash
cd src/www && mkdocs serve
```

and note that the built `assets/` tree only renders correctly when served at the
configured `site_url` root (absolute paths, search index).

## Comments
