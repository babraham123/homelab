# 04. Narrate Readeck articles labelled `listen` into Storyteller

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-11
Blocked by: 02, 03, web-archiving/02

## Problem

Articles saved in Readeck can only be read. Ones worth listening to should become
read-along books in Storyteller, with no manual export.

## Change

Flow: Readeck label `listen` → Readeck EPUB export → Calliope inbox →
`readalouds/articles/<Title>/` → Storyteller's **Articles** collection.

- `src/services/readeck/readeck_narrate.sh`, run by a systemd `.service` and `.timer` on
  websvcs every 15 minutes with `Persistent=true`. Build it on the same skeleton as
  web-archiving/03's `linkding_handoff.sh`: shared token loading, journal logging and
  the "change the label only after success" rule. Put the shared parts in a sourced
  helper rather than copying them.
  - Reach Readeck on its container IP (`.18:8000`), not through Traefik.
  - List bookmarks with `GET /api/bookmarks?labels=listen`, following pagination.
  - For each one, download `GET /api/bookmarks/{id}/article.epub` to the Calliope
    inbox as `<slug>.epub`, where `<slug>` is a filesystem-safe title plus the
    bookmark id. Write the file atomically: write a temp file, then rename it, so
    Calliope's path unit never sees a partial EPUB.
  - Write `<slug>.json` with `{"lang": <bookmark lang, default en>, "collection":
    "articles"}`.
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
- `shellcheck` passes as part of the render.

## Comments

2026-10-11, implemented in the repo as `src/services/readeck/readeck_narrate.sh.j2` with its
own `readeck_narrate` case and timer; acceptance needs a deploy.
- To avoid queueing an article twice, the script relabels without downloading when
  `<slug>` is already in the inbox, `readalouds/articles` or `failed`. That covers a
  run where the download worked but the relabel failed.
- `lang` is Readeck's `lang` reduced to its base code (`en-US` → `en`), defaulting to
  `en`.
