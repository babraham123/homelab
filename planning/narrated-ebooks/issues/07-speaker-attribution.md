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

In the fork (sections 3, "Running Qwen3-8B on the P4", 5, 6, 7, 8 and 9 of the research doc):

- `src/calliope/attribution.py`, run between `_prepare_book` and the TTS model loading, so the LLM
  has left VRAM before Chatterbox loads:
  - `LlamaServerAttributor` spawns `llama-server` on 127.0.0.1 with Qwen3-8B Q4_K_M and the
    research doc's flags (12k context, q8_0 KV cache, flash attention, `--jinja`, greedy, every
    penalty off), stdlib HTTP, killed in `finally`. `--llm-url` uses an existing OpenAI-compatible
    server instead.
  - Explicit sieve: per-language speech-verb rules label quotes tagged with a name or alias; those
    labels are locked and shown to the LLM as context.
  - Roster pass (names, aliases, gender, age, an evidence sentence); only identical full names
    auto-merge, the rest go to one consolidation prompt. The roster is frozen before attribution.
  - Attribution in chapter-bounded 8k windows that each label only their central 4k, so every quote
    gets one prediction. Static system prompt first (roster, rules, two examples in the book's
    quote style) so llama-server reuses it; passage last with inline `[Qn]` markers. Answers are
    canonical names or `_other`, under a JSON schema whose `required` lists every asked ID.
    `enable_thinking: false`.
  - Confidence from `logprobs`, renormalised over the candidate names. Quotes under
    `--min-confidence` (0.6) are re-asked in a short window with thinking on; still low, they get
    the unknown-speaker voice. Untagged two-person exchanges that break alternation are flagged in
    the report.
  - Each window's answer cached under `<work>/attribution/`, so a stopped VM loses at most one
    window.
  - Result `<work>/speakers.json` with each quote's `source` and `p`, human-editable;
    `--speakers FILE` skips attribution.
- Voice assignment: `voices.json` manifest next to the WAVs (gender, age, langs, `role: minor`).
  Deterministic: narrator is `voice`, then pinned `cast`, then the series cast, then characters by
  quote count take gender- and age-matched voices; fewer than `--min-quotes` (5) quotes share a
  minor voice; unknown speakers get the narrator. The report lists the cast.
- `--voice-mode multi`, `--voices`, `--speakers`, `--cast`, `--series-cast`, `--llm-model`,
  `--llm-url`, `--llm-ctx` (12288), `--min-confidence`, `--min-quotes`, `--strict-voices`. Without
  `--strict-voices` a failure degrades multi → dialogue → single and exits 0; over 20% of windows
  failing drops the book to dialogue.
- Containerfile: a build stage on `nvidia/cuda:12.4.1-devel-ubuntu22.04` builds a pinned llama.cpp
  tag for `CMAKE_CUDA_ARCHITECTURES=61` and copies `llama-server` and its libraries into the
  runtime image. Not the official `server-cuda` image: it is CUDA 12.8 with only PTX for Pascal,
  and CUDA 13 drops Pascal. The GGUF (`Qwen/Qwen3-8B-GGUF`, revision `7c41481`) downloads to
  `/cache`, pinned by revision and sha256.
- Tests (fake backend, no GPU): a stub OpenAI-compatible server for windowing (chapter-bounded, one
  prediction per quote), sieve labels never asked, `required` covering every asked ID, a
  byte-identical system prompt across windows, the low-confidence re-pass, cache (a rerun makes no
  requests) and fallback on bad JSON, HTTP 500 and timeouts; SIGTERM mid-pass then resume;
  `--speakers` fixture where editing one quote re-synthesizes exactly one clip; roster merge keeps
  Mr. and Mrs. Bennet apart; `assign_voices` determinism, gender match, pool exhaustion, series
  reuse.
- An opt-in accuracy script (not in CI) that scores a `speakers.json` against PDNC's gold quote and
  speaker annotations (all, explicit, implicit and anaphoric quotes) for Pride and Prejudice and a
  less famous PDNC novel (LLMs have probably memorised P&P), and against one hand-labelled
  non-English chapter. Used to pick the quant (Q4_K_M, Unsloth UD-Q4_K_XL, Q5_K_M if it fits), the
  model (Qwen3-4B-Instruct-2507 against Qwen3-8B), the prompt, `--min-confidence` and
  `--min-quotes`. One Llama-3.1-8B run calibrates the pipeline against the published 88–91%.
- Head-to-head on the same PDNC novels: BookNLP (big model), ModernBookNLP_QA and Qwen3-8B, each
  attributing the whole book, scored by the same script on the same gold quotes. Run BookNLP and
  ModernBookNLP in throwaway venvs or containers (old transformers pins; ModernBookNLP has no
  license, so it is an evaluation bar only), on CPU or the P4; they never go into the Calliope
  image. Score all with PDNC's gold quote spans, so the comparison measures attribution alone, then
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

- The head-to-head is recorded in this ticket: accuracy on all, explicit, implicit and anaphoric
  quotes, for BookNLP, ModernBookNLP_QA and Qwen3-8B with both quote sources, plus each one's
  runtime. Qwen3-8B must clearly beat BookNLP on the same books (published PDNC figures: about 40%
  for BookNLP, 88–91% for an 8B LLM given a gold character list, 94.5% for ModernBookNLP); if it
  doesn't, stop and revisit the model choice before wiring voices. Also record how far it trails
  ModernBookNLP, and what the sieve and the re-pass each add.
- On the P4, one English novel in `multi` mode: record attribution minutes per phase (roster,
  windows, re-pass), prompt and generation tokens per second, peak VRAM, the share of quotes
  re-passed, and the share of misattributed quotes in one hand-checked chapter, in this ticket.
- The same for one non-English book with dash dialogue.
- A forced attribution failure (wrong `--llm-model` path) produces a dialogue-voice book, exit 0,
  and an ntfy message saying it fell back.
- A second book with the same `series` reuses the first book's voices.
