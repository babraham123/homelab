# 04. Narrate Readeck articles labelled `listen` into Storyteller

Status: ready-for-human
Type: task
Repo: homelab, bookmark-handoff
Source: maintainer request 2026-10-11
Blocked by: 02, 03, web-archiving/02

## Problem

Articles saved in Readeck can only be read. Ones worth listening to should become
read-along books in Storyteller, with no manual export.

## Change

Flow: Readeck label `listen` → Readeck EPUB export → Calliope inbox →
`readalouds/articles/<Title>/` → Storyteller's **Articles** collection.

- The Readeck job in `bookmark_handoff.py` in the bookmark-handoff repo
  (<https://github.com/babraham123/bookmark-handoff>), which also runs web-archiving/03's linkding
  handoff, in the `bookmark_handoff` container (`src/services/bookmark_handoff/`) started by
  `bookmark_handoff.timer` on websvcs every 15 minutes with `Persistent=true`. It shares that
  handoff's API wrapper, journal logging and the "change the label only after success" rule.
  - Reach Readeck on its container IP (`.18:8000`), not through Traefik.
  - Skip the job, logging why, until Calliope's inbox exists.
  - List bookmarks with `GET /api/bookmarks?labels=listen`, following pagination.
  - For each one, download `GET /api/bookmarks/{id}/article.epub` to the Calliope
    inbox as `<slug>.epub`, where `<slug>` is a filesystem-safe title plus the
    bookmark id. Write the file atomically: write a hidden temp file, then rename it, so
    Calliope's path unit never sees a partial EPUB.
  - Write `<slug>.json` with `{"lang": <bookmark lang>, "collection": "articles"}`. The
    language is normalised with langcodes to a base code (`en-US` → `en`), and falls back to
    `en` when missing or outside Chatterbox Multilingual's languages.
  - Only after both files are in place, `PATCH /api/bookmarks/{id}` with
    `remove_labels: ["listen"]` and `add_labels: ["narrated"]`. On any failure, leave
    the label so the next run retries.
- Token: `readeck_api_token` from web-archiving/03, with the bookmarks read and
  write scopes.
- Docs: label an article `listen` in Readeck, from the browser extension or the iOS
  app. It shows up in Storyteller's Articles collection after Calliope finishes; with
  ntfy on, you're notified.

## Acceptance

- Labelling an article `listen` gives a `narrated`-labelled bookmark within one
  timer period. A read-along book for it appears in Storyteller's Articles collection
  once Calliope finishes.
- With Calliope's inbox unwritable, a run logs the failure and leaves the label as
  `listen`.
- Two runs in a row never queue the same article twice.
- The render passes, including ruff's check of the rendered Python.

## Comments

2026-10-11, implemented in the repo as `src/services/readeck/readeck_narrate.sh.j2` with its
own `readeck_narrate` case and timer; acceptance needs a deploy.

- To avoid queueing an article twice, the script relabels without downloading when
  `<slug>` is already in the inbox, `readalouds/articles` or `failed`. That covers a
  run where the download worked but the relabel failed.
- `lang` is Readeck's `lang` reduced to its base code (`en-US` → `en`), defaulting to
  `en`.

2026-10-17: fe7883f replaced `readeck_narrate.sh.j2` and its `.service`/`.timer` with the
Readeck job in `src/services/bookmark_handoff/bookmark_handoff.py`, one container and timer
shared with web-archiving/03. The duplicate check above (relabel only when `<slug>` is already
in the inbox, `readalouds/articles` or `failed`) carried over. Acceptance still needs a deploy.

2026-10-25: `bookmark_handoff.py` moved to its own repo, babraham123/bookmark-handoff, with tests
against faked linkding and Readeck APIs; tag and label names are environment variables defaulting
to `listen` and `narrated`. The homelab keeps the quadlet and timer, and `build.sh` builds the
image from that repo. Acceptance still needs a deploy.
