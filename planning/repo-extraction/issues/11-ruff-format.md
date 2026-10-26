# 11. Adopt `ruff format` in the new repos

Status: resolved
Type: task
Repo: podman-image-updater, net-probe, car-ingest, bookmark-handoff
Source: maintainer request 2026-10-25

## Problem

The new repos kept the homelab's formatting (2-space indents in places), so CI checks only
`ruff check --select E9,F`. `ruff format --check` would reformat most files in each repo.

## Change

Per repo: one commit running `ruff format`, a `ruff.toml` with the selected rules, then
`ruff format --check` and the wider `ruff check` in CI. For the two pinned host scripts, the
reformat changes the file's hash, so it lands with a pin bump in the homelab.

## Answer

Done 2026-10-25. Each repo has a `ruff.toml`: 2-space indents and 100 columns to match the
homelab, `skip-magic-trailing-comma`, and lint rules `E9,F`. Literals are formatted like
everything else, one item per line once they don't fit. CI runs `ruff check .` and
`ruff format --check .`.

| Repo | Commit |
| --- | --- |
| podman-image-updater | `25251e2` |
| net-probe | `4a03583` |
| car-ingest | `6824a94` |
| bookmark-handoff | `14c9821` |

The homelab pins moved to the podman-image-updater and net-probe commits, with their new sha256s.
