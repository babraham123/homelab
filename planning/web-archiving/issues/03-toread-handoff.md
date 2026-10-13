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

- `src/services/readeck/linkding_handoff.sh` (or a name that fits the repo better), run on
  websvcs by a systemd `.service` and `.timer` pair like
  `src/haproxy/geoip_generator.*`, every 15 minutes with `Persistent=true`.
  - Reach both apps on their container IPs (`.17:9090`, `.18:8000`) from the host, not
    through Traefik, so Authelia isn't in the path.
  - List linkding bookmarks with `GET /api/bookmarks/?q=%23toread`, following `next`
    until it runs out.
  - For each one, `POST` Readeck's `/api/bookmarks` with `url`, `title` and the other
    linkding tags as `labels`. Check the field names in Readeck's
    `docs/api/bookmarks/`.
  - Only after Readeck accepts it (2xx), `PATCH` the linkding bookmark so its tags are
    the old tags minus `toread` plus `readeck`. If any call fails, leave that bookmark
    tagged `toread` so the next run retries it. Never retry within a run.
  - Log one line per handoff and per failure to the journal; fluentbit already ships
    it.
  - Put token loading, logging and the API call wrapper in a sourced helper.
    narrated-ebooks/04 (`readeck_narrate.sh`) reuses it.
- Tokens: `linkding_api_token` and `readeck_api_token` in
  `src/nodes/websvcs/secrets_template.yaml`. The script reads them the way host-side scripts
  read secrets under ADR 0004. Don't put them in unit files.
- Install it from the `readeck` case in `install_svcs.sh`, or give it its own case and
  `src/nodes/websvcs/inventory.yml` entry if that fits the dispatcher better.
- Document the `toread` tag in the guide next to the SingleFile setup.

## Acceptance

- Tagging a bookmark `toread` in linkding makes it appear in Readeck within one timer
  period, carrying its other tags as labels. The linkding bookmark is then tagged
  `readeck` instead of `toread`.
- With Readeck stopped, a run logs failures and changes nothing in linkding. The next
  run after Readeck is back completes the handoff.
- Running the script twice in a row creates no duplicates in Readeck.
- `shellcheck` passes as part of the render.

## Comments

2026-10-11, implemented in the repo; acceptance needs a deploy to websvcs.

- `src/services/readeck/linkding_handoff.sh.j2` and its `.service`/`.timer` are installed by
  their own `linkding_handoff` case. The shared helper is `src/services/readeck/handoff_lib.sh`.
- The script reaches the apps with `curl --resolve <subdomain>:<port>:<container IP>`,
  so the Host header stays the app's own name.
- Duplicates: Readeck's API has no URL filter to check against. The script records
  each linkding id Readeck accepts in `/var/lib/linkding_handoff/sent`. If retagging
  then fails, the next run only retags the bookmark and doesn't send it again.
