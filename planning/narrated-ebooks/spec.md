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
- Storyteller (stable 2.x) on websvcs is the read-along library: it auto-imports
  Calliope's output and serves it to its apps and over OPDS (Readest, KOReader).
  Calibre integration is out of scope.
- Readeck articles labelled `listen` are narrated automatically into a Storyteller
  **Articles** collection; the label then becomes `narrated`.
- Books get a voice per character (06, 07): quotes found by rules, speakers attributed by a local
  LLM on the P4 before TTS. Articles stay in one voice. The RTX 3060 Ti is not used: same 8 GB, and
  it belongs to the gaming VM. Research: [multivoice-research.md](multivoice-research.md).

Constraints:
- The P4 (Pascal, sm_61) only runs PyTorch builds for CUDA 12.6 or older; Chatterbox
  pins `torch==2.6.0` on Python 3.10–3.13.
- websvcs is on pve2, which is on demand, so a job must survive the VM stopping
  mid-book.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-harden-calliope.md) | Fork and harden Calliope | `ready-for-human` | task |
| [02](issues/02-deploy-calliope-websvcs.md) | Run Calliope on websvcs as a GPU batch job | `ready-for-human` | task |
| [03](issues/03-deploy-storyteller.md) | Run Storyteller on websvcs as the read-along library | `ready-for-human` | task |
| [04](issues/04-readeck-listen-handoff.md) | Narrate Readeck articles labelled `listen` into Storyteller | `ready-for-human` | task |
| [05](issues/05-storyteller-mobile-access-research.md) | Research: how phones reach Storyteller, at home and away | `resolved` | research |
| [06](issues/06-dialogue-voice.md) | Split dialogue from narration and speak it in a second voice | `ready-for-agent` | task |
| [07](issues/07-speaker-attribution.md) | Give each character in a book its own voice, attributed on the P4 | `ready-for-agent` | task |
