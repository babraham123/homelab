# 02. Run Calliope on websvcs as a GPU batch job

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-11
Blocked by: 01

## Problem

Narrating a book takes hours of GPU time. It should run unattended: drop an EPUB in a
folder and later get a read-along EPUB, without logging in to the VM.

## Change

- **Build:** a `calliope` case in `src/websvcs/install_svcs.sh` that downloads the
  fork's tarball and runs `podman build -t calliope`, like `finance_exporter`. Add it
  to `src/nodes.yml` (no subdomain or uptime; it isn't a web service). If
  image-updater/04 has landed, put the recipe in `src/calliope/build.sh` instead.
- **Inbox and outbox** on the media pool:
  - `/srv/media/books/narrate/inbox`: drop `Title.epub` here, optionally with
    `Title.json` holding `{"lang": "en", "voice": "name", "collection": "books"}`.
  - `/srv/media/books/narrate/work`: the per-book cache for resuming.
  - `/srv/media/books/readalouds/<collection>/<Title>/`: the finished
    `Title.readaloud.epub` and its report. `collection` defaults to `books`. Each
    book gets its own folder because Storyteller's auto-import (03) expects one
    folder per book.
  - `/srv/media/books/narrate/failed`: inputs that failed, plus their reports.
  - `/etc/opt/calliope/voices/*.wav`: reference voices, about 15 s each.
    `default.wav` is used when no voice is given.
- **Runner:** `src/calliope/calliope.container.j2` as a oneshot quadlet
  (`Type=oneshot` in `[Service]`, no `[Install]`), with `PodmanArgs=--gpus=all` like
  `src/wyoming/whisper.container.j2` and the model cache in a named volume. It's
  started by a `calliope.path` unit that watches the inbox, plus a `calliope.timer`
  (hourly, `Persistent=true`) so a job interrupted by pve2 stopping resumes after
  boot. A small wrapper script handles one book per run, oldest first, and moves the
  input to `readalouds` or `failed` only when it finishes.
- **Sharing the GPU:** measure whisper's and Calliope's peak VRAM together on the P4's
  8 GB. If they don't fit, run Calliope at a lower priority with `Nice=`, and document
  whether voice transcription is degraded while a book is being narrated. Don't stop
  whisper automatically.
- **Monitoring:** write the job's result to the journal (fluentbit ships it). Send an
  ntfy notification when a book finishes or fails, using the same alert token as
  other websvcs scripts.
- **Backups:** voices and config are under `/etc/opt` and already staged. `work` and
  the model cache are excluded as rebuildable. `readalouds` is part of the media pool,
  which SnapRAID protects.
- **Docs:** the inbox workflow, the per-book JSON, adding a voice, and the expected
  real-time factor from 01's report. Put them in `docs/services.md` or a new
  `docs/guides/calliope.md.j2`.

## Acceptance

- Dropping a Gutenberg EPUB in the inbox produces a `.readaloud.epub` and report in
  `readalouds`, and sends an ntfy notification, with nobody logged in.
- Stopping websvcs mid-book and starting it again resumes the book without redoing
  finished sentences.
- whisper still works while a job runs, or the measured limitation is documented.
- The render passes, including shellcheck of the wrapper.

## Comments
