# 06. Link checking as a commit hook

Status: ready-for-agent
Type: task
Repo: homesite
Source: review finding 44

## Change

`.githooks/pre-commit` (activate with `git config core.hooksPath .githooks`):

1. `cd src/www && mkdocs build --strict -d /tmp/homesite-check` — `--strict` fails on
   broken internal links and missing nav targets.
2. `lychee --offline /tmp/homesite-check` for intra-site anchors, and
   `lychee --accept 200,429 'src/www/docs/**/*.md'` for external links (run the external
   pass only on `pre-push` if it's too slow for every commit). `brew install lychee`.

Document in `README.md`/`setup.md`.

## Comments
