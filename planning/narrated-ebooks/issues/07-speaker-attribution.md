# 07. Give each character in a book its own voice, attributed on the P4

Status: ready-for-agent
Type: task
Repo: TTS-Narrated-Ebook-Creator (fork), homelab
Source: maintainer request 2026-10-11; design in [multivoice-research.md](../multivoice-research.md)
Blocked by: 06

## Problem

With 06, Calliope can speak quotes in another voice but doesn't know who says them. Books should
cast each main character in a matching voice and keep it across a series. Articles stay single
voice (06).

Maintainer decisions (2026-10-11):
- Everything runs on the Tesla P4 in websvcs. The RTX 3060 Ti is not used: it has the same 8 GB, so
  it would only be faster, and it would hold the GPU the gaming VM needs for a whole book.
- Speaker attribution only for the `books` collection.

## Change

In the fork (sections 3, 5, 6, 7, 8 and 9 of the research doc):

- `src/calliope/attribution.py`, run between `_prepare_book` and the TTS model loading, so the LLM
  has left VRAM before Chatterbox loads:
  - `LlamaServerAttributor` spawns `llama-server` on 127.0.0.1 with Qwen3-8B Q4_K_M (benchmark
    Qwen3-4B-Instruct-2507 against it before pinning one), stdlib HTTP, killed in `finally`.
    `--llm-url` uses an existing OpenAI-compatible server instead.
  - Roster pass (names, aliases, gender, age), then attribution over numbered quotes in 4k-token
    chunks with 1k overlap; answers constrained by a JSON schema; Qwen3 thinking off.
  - Each chunk's answer cached under `<work>/attribution/`, so a stopped VM loses at most one chunk.
  - Result `<work>/speakers.json`, human-editable; `--speakers FILE` skips attribution.
- Voice assignment: `voices.json` manifest next to the WAVs (gender, age, langs, `role: minor`).
  Deterministic: narrator is `voice`, then pinned `cast`, then the series cast, then characters by
  quote count take gender- and age-matched voices; fewer than `--min-quotes` (5) quotes share a
  minor voice; unknown speakers get the narrator. The report lists the cast.
- `--voice-mode multi`, `--voices`, `--speakers`, `--cast`, `--series-cast`, `--llm-model`,
  `--llm-url`, `--llm-ctx`, `--min-quotes`, `--strict-voices`. Without `--strict-voices` a failure
  degrades multi → dialogue → single and exits 0; over 20% of chunks failing drops the book to
  dialogue.
- Containerfile: a build stage on `nvidia/cuda:12.4.1-devel-ubuntu22.04` builds a pinned llama.cpp
  tag for `CMAKE_CUDA_ARCHITECTURES=61` and copies `llama-server` and its libraries into the
  runtime image. Not the official `server-cuda` image: it is CUDA 12.8 with only PTX for Pascal.
  The GGUF downloads to `/cache`, pinned by revision and sha256.
- Tests (fake backend, no GPU): a stub OpenAI-compatible server for chunking, overlap merge, cache
  (a rerun makes no requests) and fallback on bad JSON, HTTP 500 and timeouts; SIGTERM mid-pass
  then resume; `--speakers` fixture where editing one quote re-synthesizes exactly one clip;
  `assign_voices` determinism, gender match, pool exhaustion, series reuse.
- An opt-in accuracy script (not in CI) that scores a `speakers.json` against PDNC's gold quote and
  speaker annotations for one novel (e.g. Pride and Prejudice, public domain), and against one
  hand-labelled non-English chapter. Used to pick the model and prompt.
- Head-to-head on that same PDNC novel: BookNLP (big model) and Qwen3-8B, each attributing the
  whole book, scored by the same script on the same gold quotes. Run BookNLP in a throwaway venv
  or container (it pins old transformers), on CPU or the P4; it never goes into the Calliope image.
  Score both with PDNC's gold quote spans, so the comparison measures attribution alone, then
  Qwen3-8B again with `quotes.py`'s spans for the end-to-end number.

In the homelab:

- `calliope_batch.py`: `books` default to `multi`. Sidecar `series` maps to
  `--series-cast /narrate/casts/<series>.json`, `cast` to a temp `--cast` file; a
  `Title.speakers.json` in the inbox becomes `--speakers`. `speakers.json` and the report are kept
  next to the book in `readalouds/books/<Title>/` for corrections.
- `/srv/media/books/narrate/casts/` created by the `calliope` install case.
- `docs/guides/reading.md.j2`: the voice library and `voices.json`, series and cast fields, and how
  to correct a speaker and re-run a book.

## Acceptance

- The head-to-head is recorded in this ticket: accuracy on all quotes and on implicit ones
  (no speaker named nearby), for BookNLP and for Qwen3-8B with both quote sources, plus each one's
  runtime. Qwen3-8B must clearly beat BookNLP on the same book (published PDNC figures: about 40%
  for BookNLP, 88–91% for an 8B LLM given a gold character list); if it doesn't, stop and revisit
  the model choice before wiring voices.
- On the P4, one English novel in `multi` mode: record attribution minutes, peak VRAM and the
  share of misattributed quotes in one hand-checked chapter, in this ticket.
- The same for one non-English book with dash dialogue.
- A forced attribution failure (wrong `--llm-model` path) produces a dialogue-voice book, exit 0,
  and an ntfy message saying it fell back.
- A second book with the same `series` reuses the first book's voices.
