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
homelab, `skip-magic-trailing-comma`, and lint rules `E9,F`. Ruff can't fill a literal across
lines, so the packed tables (car-ingest's `UNITS` and `WICAN_UNITS`, bookmark-handoff's
`narrated_langs` and its language test cases) sit between `# fmt: off` and `# fmt: on`. CI runs
`ruff check .` and `ruff format --check .`.

| Repo | Commit |
| --- | --- |
| podman-image-updater | `182213a` |
| net-probe | `93502ea` |
| car-ingest | `f52ed0e` |
| bookmark-handoff | `e906dad` |

The homelab pins moved to the podman-image-updater and net-probe commits, with their new sha256s.
