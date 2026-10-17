# 03. Hand off `toread` bookmarks from linkding to Readeck

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-11
Blocked by: 01, 02

## Problem

Bookmarks are saved once, in linkding. Ones meant for reading should show up in
Readeck without being saved a second time.

## Change

- `src/services/bookmark_handoff/bookmark_handoff.py`, run on websvcs in the
  `bookmark_handoff` container (a oneshot quadlet) by `bookmark_handoff.timer`, every 15
  minutes with `Persistent=true`. The same script also runs narrated-ebooks/04's Readeck
  `listen` job.
  - Reach both apps on their container IPs (`.17:9090`, `.18:8000`) under their public
    host names, not through Traefik, so Authelia isn't in the path.
  - List linkding bookmarks with `GET /api/bookmarks/?q=%23toread`, following `next`
    until it runs out.
  - For each one, `POST` Readeck's `/api/bookmarks` with `url`, `title` and the other
    linkding tags as `labels`.
  - Only after Readeck accepts it (2xx), `PATCH` the linkding bookmark so its tags are
    the old tags minus `toread` plus `readeck`. If any call fails, leave that bookmark
    tagged `toread` so the next run retries it. Never retry within a run.
  - Log one line per handoff and per failure to the journal; fluentbit already ships
    it.
  - Record each linkding id Readeck accepts in `/var/opt/bookmark_handoff/sent`, so a
    retry after a failed retag doesn't save it twice.
- Tokens: `linkding_api_token` and `readeck_api_token` in
  `src/nodes/websvcs/secrets_template.yaml`, passed to the container as podman secrets.
  Don't put them in unit files.
- Installed by its own `bookmark_handoff` case in `install_svcs.sh`, with a
  `bookmark_handoff: {build: bookmark_handoff}` entry in `src/nodes/websvcs/inventory.yml`.
- Document the `toread` tag in the guide next to the SingleFile setup.

## Acceptance

- Tagging a bookmark `toread` in linkding makes it appear in Readeck within one timer
  period, carrying its other tags as labels. The linkding bookmark is then tagged
  `readeck` instead of `toread`.
- With Readeck stopped, a run logs failures and changes nothing in linkding. The next
  run after Readeck is back completes the handoff.
- Running the script twice in a row creates no duplicates in Readeck.
- The render passes, including ruff's check of the rendered Python.

## Comments

2026-10-11, implemented in the repo; acceptance needs a deploy to websvcs.

- `src/services/readeck/linkding_handoff.sh.j2` and its `.service`/`.timer` are installed by
  their own `linkding_handoff` case. The shared helper is `src/services/readeck/handoff_lib.sh`.
- The script reaches the apps with `curl --resolve <subdomain>:<port>:<container IP>`,
  so the Host header stays the app's own name.
- Duplicates: Readeck's API has no URL filter to check against. The script records
  each linkding id Readeck accepts in `/var/lib/linkding_handoff/sent`. If retagging
  then fails, the next run only retags the bookmark and doesn't send it again.

2026-10-17: fe7883f replaced the shell scripts (`linkding_handoff.sh.j2`, `handoff_lib.sh`,
their `.service`/`.timer`) with `src/services/bookmark_handoff/bookmark_handoff.py` in one built
container, which also runs narrated-ebooks/04. The sent-ids state moved from
`/var/lib/linkding_handoff/sent` to `/var/opt/bookmark_handoff/sent`, which websvcs's backup
stages. Acceptance still needs a deploy to websvcs.
