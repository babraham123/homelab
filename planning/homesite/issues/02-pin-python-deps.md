# 02. Pin mkdocs and its plugins

Status: resolved
Type: task
Repo: homesite
Source: review findings 35, 40

## Change

- Add `requirements.txt` with exact versions for `mkdocs`, `mkdocs-material[imaging]`,
  `mkdocstrings`, `mkdocs-rss-plugin`, `mkdocs-awesome-nav` (take the versions currently
  installed via `pipx runpip mkdocs freeze`).
- Replace the `pipx` instructions in `setup.md` with `uv venv && uv pip install -r
  requirements.txt` (uv is already on the workstation) and have `tools/render_src.sh`
  invoke `.venv/bin/mkdocs`.
- Bump deliberately, on purpose, a couple of times a year; no Renovate (maintainer
  decision).

## Comments
