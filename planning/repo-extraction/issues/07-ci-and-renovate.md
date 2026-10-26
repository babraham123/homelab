# 07. CI and Renovate for the new repos and the fork

Status: resolved
Type: task
Repo: podman-image-updater, net-probe, car-ingest, bookmark-handoff, haproxy-mapper (fork)
Source: maintainer request 2026-10-25
Blocked by: 01, 02, 03, 04, 06

## Change

CI and Renovate in each repo, following yt-to-audiobook's setup.

## Answer

Done 2026-10-25 (podman-image-updater `9db59c2`, net-probe `48e4845`, car-ingest `8f072f2`,
bookmark-handoff `02aec4a`, haproxy-mapper `48ebd12` on `geoip-generator`).

- **CI** (`.github/workflows/ci.yml`): Actions pinned by digest; `uvx ruff@0.17.0 check --select
  E9,F` (the homelab pre-commit hook's level); `python3 -m unittest discover -s tests`. Python 3.13
  for the two host scripts (Debian trixie's), 3.14 for the containers (their base image).
  bookmark-handoff installs its hashed requirements first. car-ingest and bookmark-handoff build
  their image (no push).
- **haproxy-mapper:** `go.yml` keeps the Go build and tests, now on pinned Actions with the Go
  version from `go.mod` (still 1.16), plus a ruff job and an image build for the generator.
- **Renovate** (`renovate.json`): `config:recommended`, `helpers:pinGitHubActionDigests`, Monday
  before 6 am, 3-day minimum release age, Actions grouped; with a Containerfile,
  `docker:pinDigests` and base images grouped; bookmark-handoff's `requirements.txt` through
  pip-compile; haproxy-mapper's Go modules grouped; a regex manager for the `ruff@` version in the
  workflows. Digest-pinned `FROM` lines still work with `github_build`, as in yt-to-audiobook.
- Each repo's tests pass locally under the CI Python version. CI itself first runs on the push
  (08).
