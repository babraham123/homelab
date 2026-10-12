# 01. Fork and harden Calliope

Status: ready-for-human
Type: task
Repo: babraham123/TTS-Narrated-Ebook-Creator (fork of hugohammer/TTS-Narrated-Ebook-Creator)
Source: maintainer request 2026-10-11

## Problem

Calliope works as a one-off script on a workstation. Running unattended on a shared
Pascal GPU, on a VM that can stop mid-book, it would lose progress, could ship
garbled sentences, and has no container image.

## Change

Fork to `github.com/babraham123/TTS-Narrated-Ebook-Creator`, like the other forks the homelab builds
from. Keep upstream's layout so fixes can go back as PRs.

- **Model choice:** a `--model turbo|multilingual` flag. Turbo
  (`chatterbox.tts_turbo`, English only) is the default for `en`. Multilingual
  (`ChatterboxMultilingualTTS`, what upstream loads today) is used for other
  languages. Check the class names against the installed `chatterbox-tts`.
- **Pinned dependencies for the P4:** Python 3.12, `torch==2.6.0` and
  `torchaudio==2.6.0` from the CUDA 12.4 or 12.6 index, matching `chatterbox-tts`'s
  own pin, plus a lock file. Pin `chatterbox-tts` too.
- **Resumable:** cache each sentence's audio under a work directory keyed by a hash of
  book, sentence text, model, voice and settings. Rerunning the same book skips
  finished sentences, and only the SMIL and packaging are redone. Killing the process
  at any point and rerunning must produce the same EPUB.
- **Quality check per sentence:** reject clips whose duration is far outside what the
  text length predicts (too short means truncated; too long means rambling or noise),
  and clips that are mostly silence. Retry a rejected clip with a new seed up to N
  times, then keep the best attempt and list it in a report. Optional, behind a flag:
  transcribe each clip with faster-whisper and flag clips whose word error rate is
  above a threshold.
- **Output:**
  - Encode audio as MP3 or AAC, not Opus, since some readers can't play Opus.
  - One audio file per chapter.
  - Set the `media:duration` metadata and a `-epub-media-overlay-active` CSS class.
  - The output EPUB must pass `epubcheck` with no errors.
- **Interface:** a CLI that takes `IN.epub OUT.epub --voice WAV --lang xx`, exits
  non-zero on failure, and writes a JSON report next to the output (sentences, retries,
  flagged clips, run time, real-time factor).
- **Container:** a `Containerfile` on a CUDA 12.x runtime base with ffmpeg and the
  pinned stack. The model weights download to a mounted cache directory, not into the
  image.
- Send the general fixes (resume, QA, epubcheck, packaging) upstream as PRs.

## Acceptance

- A short public-domain book (Project Gutenberg) converts in the container on the P4.
  The result passes `epubcheck`, and plays with sentence highlighting in Readest (at
  1.0×) and in the Storyteller app.
- Killing the job halfway and rerunning finishes without re-synthesizing the
  sentences already done.
- A sentence forced to fail the quality check (for example a test hook that returns
  silence) is retried and shows up in the report.
- The report gives the P4's real-time factor for Turbo and Multilingual.

## Comments

2026-10-11: implemented in 12 commits, fast-forwarded onto the fork's `main`
(`89954aa`).
- **CLI:** `calliope IN.epub OUT.epub --voice WAV --lang xx [--model turbo|multilingual]
  [--work-dir DIR]`, plus QA flags (`--max-retries`, `--max-silence`,
  `--whisper-check`, `--wer-threshold`).
  - The report is `OUT.report.json`, OUT with its extension replaced.
  - `real_time_factor` is wall seconds per audio second, so lower is faster.
  - Exit codes: 0 ok, 1 failure, 2 usage, 143 on SIGTERM, which leaves the cache
    valid.
  - Test hook: `CALLIOPE_FORCE_SILENCE`.
- **Verified names:**
  - `chatterbox.tts_turbo.ChatterboxTurboTTS`, weights `ResembleAI/chatterbox-turbo`.
  - `chatterbox.mtl_tts.ChatterboxMultilingualTTS`, weights `ResembleAI/chatterbox`.
- **Pins:**
  - `chatterbox-tts==0.1.7`
  - `torch`/`torchaudio==2.6.0+cu124`; the cu124 build includes sm_60, which runs on
    the P4's sm_61.
  - `ctranslate2==4.6.2`, the last build for CUDA 12.4.
  - `setuptools<82`: resemble-perth needs `pkg_resources`. Without the pin, no fresh
    install loads either model.
  - A cross-platform `uv.lock`.
- **Container:** `Containerfile` on `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04`,
  with Python 3.12 from uv in `/opt/venv` and `HF_HOME=/cache`.
- **Tested:**
  - 24 pytest tests with a fake backend: resume gives a byte-identical EPUB, SIGTERM
    at two points, QA retries, whisper flagging, report contents, SMIL and package
    structure.
  - epubcheck 5.4.0 passes.
  - Real CPU runs of Turbo (English) and Multilingual (Norwegian) worked.
- **Not yet done:**
  - Building the image (no podman on the Mac).
  - Any GPU or P4 run, so the real-time factors are still missing.
  - Upstream PRs. Most commits depend on the first, which restructures the code into
    a package.
