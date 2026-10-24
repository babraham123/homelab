# 01. Hand linkding `tolisten` bookmarks to the video inbox

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-23

## Problem

A YouTube video should enter the pipeline the way an article does: tag it in the linkding
extension or Pinkt and forget it. `bookmark_handoff.py` already moves `toread` bookmarks to
Readeck and `listen` articles to Calliope's inbox every 15 minutes; it needs a third job.

## Change

- **Job:** `linkding_to_video(linkding)` in `src/services/bookmark_handoff/bookmark_handoff.py`,
  after `readeck_to_narrate` in `main()`'s job list, so each job runs whatever the others did.
  - Query `/api/bookmarks/?q=%23tolisten&limit=100`, all pages first, as `linkding_to_readeck`
    does.
  - For each bookmark write `/videos/inbox/<slug>.json`:
    `{"url": ..., "title": ..., "linkding_id": N, "lang": <tag lang:xx if present>}`.
    `slug` follows the existing `slug()` helper: title, then `-<linkding id>` to keep
    duplicates apart. Write to a dotted temp name and rename, so `yt_to_audiobook.path` never
    sees a partial file.
  - Retag `tolisten` → `transcribed` with the existing PATCH. A failed write keeps the tag and
    the next run retries; a failed retag after a successful write is logged and retried, like
    the other jobs.
  - Idempotency: the request is already queued, done or failed when any of
    `inbox/<slug>.json`, `readalouds/videos/<slug>/`, `failed/<slug>/` exists; then retag only.
    Same shape as `readeck_to_narrate`'s `done` list.
  - If `/videos/inbox` doesn't exist yet (02 not installed), log and return `0, 0`, as the
    narrate job does for Calliope.
- **Quadlet:** add `Volume=/srv/media/books/videos:/videos` to
  `src/services/bookmark_handoff/bookmark_handoff.container.j2`. The install case already
  requires the media mount.
- **Install:** `mkdir -p /srv/media/books/videos/inbox` in the `bookmark_handoff` case of
  `src/nodes/websvcs/install_svcs.sh`, so the job works before 02 is installed.
- **Docs:** the header comment in `bookmark_handoff.py` and the "Listen" section of
  `docs/guides/reading.md.j2` gain the `tolisten` tag.

## Acceptance

- A bookmark tagged `tolisten` produces `inbox/<slug>.json` within 15 minutes and is retagged
  `transcribed`; a second run changes nothing.
- A bookmark tagged while the inbox directory is missing keeps its tag, and the run exits 0.
- The render passes.
