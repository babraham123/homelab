# 02. Fetch the audio and captions and build the read-along EPUB

Status: ready-for-agent
Type: task
Repo: homelab, yt-to-audiobook
Source: maintainer request 2026-10-23
Blocked by: 01

## Problem

Given a request in the inbox, produce a read-along EPUB that Storyteller imports, with the
sponsor reads cut out and the highlight in sync, unattended, surviving pve2 going down.

## Change

Service `src/services/yt_to_audiobook/`, modelled on Calliope's runner, not on the handoff.

- **Image:** `yt_to_audiobook.Containerfile` from `python:3-alpine` by digest, `apk add ffmpeg`,
  `yt-dlp` pinned by hash in `requirements.txt` (`uv pip compile --generate-hashes
  --universal`). `build.sh` is a copy of `bookmark_handoff/build.sh`; its `versions` output
  includes the files hash, so a yt-dlp bump rebuilds through the image updater's scan gate.
  Add `yt_to_audiobook: {build: yt_to_audiobook}` to `src/nodes/websvcs/inventory.yml`.
- **Directories** on the media pool, created by the install case:
  - `/srv/media/books/videos/inbox`: `<slug>.json` requests from 01
  - `/srv/media/books/videos/work/<slug>/`: yt-dlp output and the EPUB staging dir; a run
    cut short by pve2 stopping resumes from here (`yt-dlp --continue`)
  - `/srv/media/books/videos/failed/<slug>/`: the request and whatever was fetched
  - `/srv/media/books/readalouds/videos/<Title>/Title.readaloud.epub`: output, chowned
    `1000:1000` like Calliope's, EPUB written last via a dotted temp name and `os.replace`
- **Runner** `batch/yt_to_audiobook_batch.py` in yt-to-audiobook, baked into the image at
  `/opt/yt_to_audiobook_batch.py` and run as the quadlet's entrypoint, like Calliope's
  `calliope_batch.py`. One request per run, oldest first:
  1. `yt-dlp` with `-f "ba[ext=m4a]" --embed-metadata --embed-thumbnail --write-info-json
     --write-subs --write-auto-subs --sub-lang <lang>,<lang>-orig --sub-format vtt
     --sponsorblock-mark sponsor,selfpromo,interaction,intro,outro,preview --continue
     --no-playlist -o "work/<slug>/%(id)s.%(ext)s"`. `lang` from the request, default `en`.
  2. Cuts: read `sponsorblock_chapters` from `info.json`. Drop every cue inside a segment,
     shift the rest by the removed time before them, and cut the audio with one ffmpeg
     `-c copy` pass over the kept intervals. Record the cuts in the report.
  3. No VTT: with 04 absent, move to `failed/` and notify "no captions". With 04 present,
     call it to get cues in the same VTT shape, then continue.
  4. EPUB 3 with Media Overlays: one XHTML chapter (split at SponsorBlock `chapter` segments
     or every 10 minutes if there are none), one `<p id>` per cue, the SMIL `<par>` per cue
     from its start and end, the m4a as the audio resource, the thumbnail as the cover,
     `dc:title` from the video title, `dc:creator` the uploader, `dc:source` the URL,
     `dc:language` from the caption language. Stdlib `zipfile` and `xml.etree`; no new
     libraries beyond yt-dlp. Validate with `epubcheck` once by hand; not in the job.
  5. A JSON report beside the EPUB: video id, caption source (uploaded, auto, stt), cue
     count, cuts, duration before and after.
  6. ntfy "Read-along done" (priority 3) or "Read-along failed" (priority 4), with
     `X-Tags: books`, through the same `ntfy_alert_token` secret Calliope uses.
  7. SIGTERM leaves the request in the inbox and `work/<slug>` in place; `TimeoutStopSec=90`.
- **Units:** `yt_to_audiobook.container.j2` (`Type=oneshot`, `ReadOnly=true`,
  `DropCapability=all`, `NoNewPrivileges=true`, IP `{{ websvcs.container_subnet }}.25`,
  `TimeoutStartSec=2h`, volumes for `/videos` and `/readalouds`; no GPU),
  `yt_to_audiobook.path` with `PathExistsGlob=/srv/media/books/videos/inbox/*.json`, and
  `yt_to_audiobook.timer` (hourly, `Persistent=true`, `OnBootSec=5min`) as the backstop,
  copied from Calliope's pair. The install case enables both.
- **Storyteller:** the `videos` collection is a folder under `readalouds`; the Storyteller
  case adds it to its `mkdir -p` and `chown`, and the library import picks it up like
  `articles`.
- **Backups:** `src/nodes/websvcs/backup.sh.j2` excludes `/srv/media/books/videos`; the
  readalouds tree is media, parity only, as today.
- **Docs:** `docs/services.md` catalog row and host-services row (path + timer), the
  "Listen" section of `docs/guides/reading.md.j2` (tag, `lang:xx` tag, where the output
  goes, the failed folder, the yt-dlp bump chore), and the test fixture if
  `check_rendered.py` needs one for the new build service.

## Acceptance

- A `tolisten`-tagged talk with captions is in Storyteller's Videos collection within an
  hour, plays in the Storyteller app with the transcript highlighted, and the sponsor read
  is gone with the highlight still in sync after it.
- A video without captions ends in `failed/` with an ntfy notification, and the request
  moved back to the inbox is retried.
- Stopping websvcs mid-download and starting it again finishes the same request without
  re-downloading what it had.
- The render passes, including shellcheck of `build.sh`.

## Comments

- 2026-10-23: the converter moved to its own repo,
  [babraham123/yt-to-audiobook](https://github.com/babraham123/yt-to-audiobook), which pins
  yt-dlp, yt-dlp-ejs and mutagen and has its own Containerfile, CI and Renovate. `build.sh` is
  now `github_build` from its `main`, like Calliope's. The runner stays here as
  `src/services/yt_to_audiobook/yt_to_audiobook_batch.py`, bind-mounted and calling
  `convert()`; it owns the inbox, `failed/`, delivery to `readalouds/videos/<slug>/` and ntfy.
  The yt-dlp bump in "Image" above is now a Renovate PR in that repo.
- 2026-10-25: the runner moved into yt-to-audiobook as `batch/yt_to_audiobook_batch.py`, baked
  into the image at `/opt/yt_to_audiobook_batch.py` with `VIDEOS_DIR` and `READALOUDS_DIR`
  defaulting to `/videos` and `/readalouds`. The quadlet no longer mounts a script; a runner edit
  ships through the image's rebuild, like the converter.
