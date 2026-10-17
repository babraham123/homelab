# 06. Split dialogue from narration and speak it in a second voice

Status: ready-for-agent
Type: task
Repo: TTS-Narrated-Ebook-Creator (fork), homelab
Source: maintainer request 2026-10-11; design in [multivoice-research.md](../multivoice-research.md)
Blocked by: 01, 02

## Problem

Calliope narrates a whole book in the one `--voice` WAV, and `_QUOTES` strips the quote marks
before synthesis, so every character speaks in the narrator's voice. Multi-voice books (07) need
quotes found, sentences split into voiced segments and a backend that switches voices. Built on its
own, that same machinery gives a cheap mode: all quoted speech in one alternate "dialogue voice",
with no character tracking. It is also 07's fallback.

## Change

In the fork (sections 1, 2, 4, 5, 6 and 8 of the research doc):

- `src/calliope/quotes.py`: `find_quotes(block_text, lang) -> [(start, end)]`, rule tables for the
  ten normaliser languages (curly, „“, »«, « », ”” and dash dialogue), multi-paragraph quotes,
  apostrophes vs closing ‘’, nested quotes kept with the outer speaker.
- `epub.process_xhtml_inplace`: each sentence gains `segments [{text, quote}]`, from its span
  intersected with the quote spans; empty or punctuation-only segments are dropped. Still one
  `<span id>` and one `<par>` per sentence, so XHTML and SMIL don't change. Quote IDs are
  `<chapter>.<block>.<ordinal>`.
- `tts.py`: `generate(text, seed, voice)`. `ChatterboxBackend` caches conditionals per voice and
  swaps `model.conds`, so one model in VRAM serves every voice. `FakeBackend` picks its frequency
  band from the voice hash.
- `pipeline.py`/`cache.py`: synthesis, QA and retries work on clips (sentence + segment); each
  clip's key is the existing `clip_key` with its own voice hash. A sentence's wav is its clips
  trimmed, joined with ~0.1 s gaps and loudness-matched. **Single-voice mode must produce the same
  clip keys and byte-identical output as now** (no `CACHE_VERSION` bump).
- CLI: `--voice-mode single|dialogue` (default `single`), `--dialogue-voice WAV`. Report gains
  `voices: {requested, used, reason}`. No quotes found: single voice, exit 0.
- Tests with the fake backend, expected values from the punctuation rules: dialogue chapters in en
  (`“Run,” she said.`, a two-sentence quote, a multi-paragraph quote), de (`„…“`) and es (dash
  dialogue); one `<par>` per sentence; quote clips in the dialogue voice's band and the tag in the
  narrator's; epubcheck passes; the single-mode regression guard above; `quotes.py` tables per
  language.

In the homelab:

- `calliope_batch.py`: sidecar fields `voice_mode` and `dialogue_voice` (a name in
  `/etc/opt/calliope/voices`, checked like `voice`), mapped to the flags. The default comes from the
  collection: `articles` → `single`, `books` → `dialogue` until 07 lands. The ntfy message says when
  a run fell back.
- `src/services/bookmark_handoff/bookmark_handoff.py`: write `voice_mode: "single"` into each
  article's sidecar, so articles never pay for segmentation or attribution.
- `docs/guides/reading.md.j2`: the sidecar fields, and a `dialogue.wav` next to `default.wav`.

## Acceptance

- `pytest` passes in the fork, including the single-mode regression guard.
- On the P4, one English and one non-English book in `dialogue` mode: quotes are audibly in the
  dialogue voice, highlighting stays in sync in Storyteller, and the report records how many
  segments under 3 characters QA flagged.
- A Readeck article still narrates in one voice, and its clip keys match a run before this change.
