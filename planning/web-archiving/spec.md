# Web archiving and read-it-later

Replaces ArchiveBox, which was removed along with its noVNC sidecar because Chromium
needed a display to log in to sites. The new setup needs no display on the
server: pages are captured in the user's own logged-in browser, with linkding's
headless snapshot as the fallback.

- **linkding** on websvcs is the bookmark library and page archive. The SingleFile
  browser extension uploads full-page snapshots to it.
- **Readeck** on websvcs is the reader: extracted article text, highlights, EPUB/OPDS.
- A timer hands off any linkding bookmark tagged `toread` to Readeck.

Maintainer decisions (2026-10-11):
- linkding's `latest-plus` image, so bookmarks saved without SingleFile (from Pinkt,
  the Android client) still get a server-side snapshot. Chromium runs only during a
  snapshot.
- linkding trusts Authelia's `Remote-User` header. Readeck uses Authelia OIDC, since
  0.23 removed proxy-header auth.
- The handoff tag is `toread`. After a handoff, the bookmark's `toread` tag is swapped
  for `readeck`, so the bookmark stays in linkding and is never sent twice.
- No AI extraction or summaries; Readeck's Readability and site rules are enough.
- Text-to-speech comes from the client (the third-party Readeck iOS app, or OS read
  aloud), not from the server.

Constraint: websvcs is on pve2, which is on demand, so captures and handoffs only run
while pve2 is up. Accepted.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-linkding-singlefile.md) | Run linkding on websvcs with SingleFile uploads | `ready-for-human` | task |
| [02](issues/02-readeck.md) | Run Readeck on websvcs with Authelia OIDC | `ready-for-human` | task |
| [03](issues/03-toread-handoff.md) | Hand off `toread` bookmarks from linkding to Readeck | `ready-for-human` | task |
