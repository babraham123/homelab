# 04. Transcribe captionless videos with Parakeet on the CPU

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-23
Blocked by: 02, 03

## Problem

Music, very fresh uploads and some non-English videos have no captions, uploaded or
automatic, so 02 fails them. The fallback should produce cues in the same shape 02 builds
from, without the P4 and without a second engine.

## Change

- **Engine:** NVIDIA Parakeet TDT 0.6B v3, English and 24 other European languages, run on
  the CPU through `sherpa-onnx` (or `parakeet.cpp` if its Alpine build is simpler), with
  word timestamps and punctuation from the model. Chosen over faster-whisper for English
  accuracy and speed and for staying off the P4's CUDA 12.6 pin; chosen alone, since a rare
  path doesn't justify two engines. A captionless video in a language Parakeet doesn't cover
  fails as in 02.
- **Where it runs:** inside the `yt_to_audiobook` image, as a module `stt.py` next to the
  runner. The model (about 600 MB of ONNX) lives in a named volume, `yt_to_audiobook_models`,
  pulled on first use by a pinned URL and checksum in the script, never at build time.
- **Output:** a VTT written to `work/<slug>/<id>.stt.vtt`, cues of one sentence or at most
  about 15 words, timestamps from the first and last word, so 02's builder and cut logic
  don't change. The report records `caption source: stt`.
- **Resources:** `Nice=10` is already on the unit; measure the real-time factor on websvcs'
  vCPUs and put it in the docs. If an hour of audio takes more than about 20 minutes,
  raise `TimeoutStartSec` and note it.
- **Decision gate:** if 03 found Storyteller's own alignment acceptable, this issue becomes
  "upload the m4a and a transcript EPUB to Storyteller's API instead of building the SMIL",
  with Parakeet still producing the transcript text.

## Acceptance

- A captionless English talk is in the Videos collection with a usable highlight, with
  nobody logged in.
- The P4 is untouched during the run (`nvidia-smi` shows no new process).
- A captionless Japanese video fails with the "no captions" notification, not a crash.
- The render passes.
