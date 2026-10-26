# 08. Create and push the repos, fast-forward the forks

Status: ready-for-human
Type: task
Repo: podman-image-updater, net-probe, car-ingest, bookmark-handoff, haproxy-mapper,
  TTS-Narrated-Ebook-Creator, yt-to-audiobook, homelab
Source: maintainer request 2026-10-25
Blocked by: 01, 02, 03, 04, 05, 06, 07

## Problem

Everything is committed locally only. The pinned downloads and `github_build` read GitHub, so
nothing deploys until the repos are there.

## Change

In this order:

1. New repos, public (the nodes fetch them without credentials), pushed as they are:

   ```bash
   for r in podman-image-updater net-probe car-ingest bookmark-handoff; do
     gh repo create "babraham123/$r" --public --source ~/Personal/$r --remote origin --push
   done
   ```

   Don't amend or rebase podman-image-updater or net-probe first: the homelab pins their
   current heads (`25251e2`, `4a03583`). If either changes, update `commit` and `sha` in its case in
   `src/base/debian/install_svcs.sh`.
2. Existing repos, fast-forwarding `main` to the work branches:

   ```bash
   git -C ~/Personal/haproxy-mapper push origin geoip-generator:main
   git -C ~/Personal/TTS-Narrated-Ebook-Creator-batch push origin batch-entrypoint:main
   git -C ~/Personal/yt-to-audiobook-batch push origin batch-entrypoint:main
   ```

3. Homelab: `git merge --ff-only extract-components` on `main`, then push.
4. Enable the Renovate app on the four new repos.
5. Once merged: remove the `TTS-Narrated-Ebook-Creator-batch` and `yt-to-audiobook-batch`
   worktrees, the homelab's extraction worktrees and their branches.

## Acceptance

- CI is green on each new repo's first push and on the forks' `main`.
- `curl -fsS` of each pinned raw URL in `src/base/debian/install_svcs.sh` returns a file whose
  sha256 matches its `sha`.
- Renovate opens its onboarding PR on each new repo.
