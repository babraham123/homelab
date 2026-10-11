# Narrated ebooks with Calliope

Turn DRM-free EPUBs into read-along EPUBs (EPUB 3 Media Overlays) with local TTS, so
any book can be read and listened to with the text highlighted.
[Calliope](https://github.com/hugohammer/TTS-Narrated-Ebook-Creator) (MIT) already
does this with Chatterbox. It splits each chapter into sentences, wraps each sentence
in a `<span id>`, synthesizes it, and writes the SMIL from the clip lengths, so it
needs no forced alignment. It is research code (15 stars, last pushed 2026-05-13),
so it is forked and hardened before it runs unattended.

Maintainer decisions (2026-10-11):
- Calliope, not Storyteller alignment of a synthetic audiobook: the timings are exact
  and it saves hours of alignment per book.
- Runs on websvcs, on the Tesla P4 it shares with whisper. Jobs are batch, one book
  at a time; speed is secondary.
- Chatterbox Turbo for English (faster), Multilingual for other languages.
- Output is read in Readest or Storyteller's apps; Calibre-side integration is out of
  scope here.

Constraints:
- The P4 (Pascal, sm_61) only runs PyTorch builds for CUDA 12.6 or older; Chatterbox
  pins `torch==2.6.0` on Python 3.10–3.13.
- websvcs is on pve2, which is on demand, so a job must survive the VM stopping
  mid-book.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-harden-calliope.md) | Fork and harden Calliope | `ready-for-agent` | task |
| [02](issues/02-deploy-calliope-websvcs.md) | Run Calliope on websvcs as a GPU batch job | `ready-for-agent` | task |
