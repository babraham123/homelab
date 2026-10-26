# 11. Adopt `ruff format` in the new repos

Status: needs-triage
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
