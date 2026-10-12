# Multi-voice narration for Calliope: speaker attribution research and design

Research for 06 and 07, 2026-10-11. (est.) marks estimates that are neither sourced nor measured on
the P4. The maintainer chose to run everything on the P4 (no RTX 3060 Ti) and to narrate articles
in a single voice.

## Recommendation

1. **Quote detection: rule-based, per language, inside Calliope.** It is deterministic, testable,
   and gives exact character offsets. The offsets are needed to split sentences, and an LLM can't be
   trusted to return them.
2. **Speaker attribution: a local LLM through `llama-server` (llama.cpp)**, built for sm_61 on CUDA
   12.4 inside the Calliope image.
   - Model: **Qwen3-8B Q4_K_M** (Apache-2.0, multilingual). Benchmark it against
     Qwen3-4B-Instruct-2507 before pinning one.
   - It runs in two passes over the book, both returning JSON constrained by a schema:
     - **Roster pass:** characters with aliases, gender and age.
     - **Attribution pass:** numbered quotes in 4k-token chunks, mapped to roster IDs.
   - This is the only approach that covers all ten languages with one code path. It is also the
     published LLM state of the art in this size class: Llama-3-8B scores 88.5–90.6% on PDNC given a
     gold character list.
3. **It runs as a separate phase before TTS, in the same `calliope` process.** The LLM (~6.5 GB with
   8k context, est.) and Chatterbox (fp32, ~3–4 GB, est.) don't fit together in the P4's 8 GB.
   Calliope already loads the TTS model lazily after `_prepare_book`, so attribution slots in
   between, and its subprocess exits (freeing VRAM) before Chatterbox loads. The wyoming whisper
   quadlet is "not in use" (`docs/services.md`), so nothing else contends for the GPU.
4. **Cost:** about 30–90 min of P4 time per novel (est.), against an estimated 10–25 h of TTS.
   That's under 10% overhead.
5. **Build the cheap mode first:** a dialogue voice (all quoted speech in one alternate voice, no
   character tracking). It needs the same segmentation, multi-voice backend and cache changes, but
   no ML. Multi-voice is then an attributor plugged into a working pipeline.
6. **Not now:**
   - BookNLP: 0.40 accuracy on PDNC and English only.
   - ModernBookNLP_QA: 92–94.5% on PDNC, English only, no license, 2 commits, and pins transformers
     4.57 against Chatterbox's 5.2. Revisit as an English-only attribution backend once it has a
     license.
   - Cloud LLMs: the API is OpenAI-compatible, so `--llm-url` could point at one, but the whole book
     text would leave the house (~200k input tokens per novel). Off by default.

## Comparison

| Approach | Accuracy (PDNC, English) | Non-English | P4 fit / time per novel | License / maturity | Verdict |
|---|---|---|---|---|---|
| Rule-based sieve (Muzny 2017) | F 87.5 on 3 novels; precision 90.4 at recall 65.1 in high-precision mode; collapses on implicit quotes | Rules per language; none published for da/no/sv etc. | CPU, seconds | Easy to write | Use for **quote detection** only; attribution heuristic not worth it |
| BookNLP (original, big/small) | 0.40 on PDNC (0.28 on implicit); B3 89.9/86.4 on its own data | English only | ~2–5 min on GPU or CPU | MIT; dormant since 2024; old transformers | Reject |
| BookNLP+ (retrained on PDNC) | 78.5 / 79.2 | English only | Minutes | Research code | Reject |
| ModernBookNLP_QA (Michel et al., Aug 2026) | **94.5** joint (9.2 GB VRAM); **92.3** direct (2.4 GB); assumes a character list | English only (ModernBERT) | Fits (direct variant); seconds | **No license**, 2 commits, transformers 4.57 pin | Future English upgrade, in its own venv |
| Llama-3-8B, 8-bit, gold character list (Michel et al., NAACL 2025) | **90.6** (PDNC1), 88.5 (PDNC2); ChatGPT ~71 | Untested; model-dependent | 14 GB at 8-bit; 10–60 min on A5000. At Q4 on a P4: ~6.5 GB, ~30–90 min (est.) | Llama license | Method to copy |
| **Qwen3-8B Q4_K_M via llama.cpp** (recommended) | Not published; expect high 80s for English with an LLM-built roster (est.) | Qwen3 claims 119 languages, covers all ten | ~5 GB weights + ~1.2 GB KV at 8k ctx; ~30–90 min (est.) | Apache-2.0; llama.cpp MIT | **Use** |
| Gemma-3-12B / Mistral-NeMo-12B Q4 | n/a | Good | ~7–7.5 GB weights: too tight | Gemma terms / Apache | No |
| Ollama instead of llama-server | Same models | Same | Docs list compute capability 6.1 (driver ≥570); Pascal support relies on the CUDA 12 runner continuing | MIT | Works, but adds a daemon; `llama-server` as a child process is simpler |
| Dialogue voice only (no attribution) | n/a (quote detection ~0.94 on PDNC for BookNLP's detector) | Same rules | None | Own code | **Ship first** and keep as the fallback |

### How existing multi-voice projects do it

- **audiobook-creator** (GPL-3.0): two-step LLM (characters with age and gender, then line
  attribution) through an OpenAI-compatible endpoint. Voices come from gender scores in
  `character_gender_map.json`. English only.
- **Alexandria** (MIT): an LLM writes a structured script (Gemma3-27B recommended), with an optional
  LLM review pass and speaker aliases. Voices are presets, clones or generated "personas".
- **VoxNovel** (MIT): BookNLP plus a GUI for corrections. Voices are picked by pronoun gender, with
  per-character overrides. English only.
- **No automatic attribution:** Pandrator (manual character voices), ebook2audiobook (manual
  `[voice:]` tags), epub2tts (per-chapter speaker).
- **Takeaway:** the active projects converged on LLM roster plus attribution, a gender-matched voice
  pool, and an editable mapping file. None attribute non-English text out of the box.

## Voice assignment

- **Voice library manifest:** `/etc/opt/calliope/voices/voices.json`, next to the WAVs, mapping each
  name to its gender, age, languages and role:
  ```json
  {"default": {"gender": "m", "age": "adult", "langs": ["en"]},
   "f1": {"gender": "f", "age": "adult"}, "f_old": {"gender": "f", "age": "elderly"},
   "m_minor": {"gender": "m", "role": "minor"}, "f_minor": {"gender": "f", "role": "minor"}}
  ```
  - Aim for 4–6 voices per gender across age bands.
  - Use `langs` per voice: Chatterbox Multilingual speaking German in a voice cloned from English
    has an accent.
- **Deterministic assignment**, so a rerun gives the same cast:
  1. The narrator is the sidecar `voice`.
  2. Pinned voices come from the sidecar `cast` (`{"Elizabeth Bennet": "f1"}`), then from the series
     cast file.
  3. The remaining characters are sorted by quote count, descending, then by name. Each takes the
     first unused voice in manifest order that matches its gender (unknown matches any) and prefers
     its age band. Never reuse the narrator's voice.
  4. When the pool runs out, or a character has fewer than 5 quotes (default), it gets the gender's
     `role: minor` voice.
  5. Unknown or low-confidence speakers get the narrator voice, or the dialogue voice in dialogue
     mode. A neutral voice is less jarring than a wrong character's voice.
- **Series consistency:** a sidecar `"series": "discworld"` reads and writes
  `/srv/media/books/narrate/casts/<series>.json`, which holds each canonical name, its aliases and
  its voice.
  - Before assigning, roster entries are matched to series entries by normalised name or alias
    (case- and diacritic-folded).
  - New main characters are appended after a successful run. The file sits on the media pool
    (SnapRAID) and is hand-editable.
- **The resolved cast goes in the run report** (`cast`: character → voice and quote count), so the
  ntfy and report path shows who got which voice.

## Integration design (Calliope, branch `harden`)

### Data flow in `pipeline.run`

```
_prepare_book    -> chapters -> sentences, each with segments [(text, quote_id|None)]; blocks with quote spans
attribute()      -> speakers.json (cached; skipped when mode is single or dialogue)
assign_voices()  -> quote_id -> voice name -> voice path
clip keys        -> one key per segment
synthesis        -> unique segment clips (unchanged retry/QA loop)
assembly         -> sentence wav = its segment clips joined; chapter = sentences (unchanged SMIL)
```

### 1. Quote detection: new `src/calliope/quotes.py`

- `find_quotes(block_text, lang) -> [(start, end)]` over the whitespace-normalised `full_text_clean`
  that `process_xhtml_inplace` already computes per block.
- Pair styles per language:

  | Languages | Styles |
  |---|---|
  | en | “” ‘’ "" |
  | de | „“ »« ‚‘ |
  | fr, it | « » (narrow no-break spaces) |
  | sv, fi | ”” »» |
  | da, no | « » and »« |
  | nl | ‘’ “” „” |
  | pt | « » “” |

- Dash dialogue (es, it, pt, fr, the Scandinavian languages, nl): a block starting with `—` or `–`
  is speech up to the next incise dash (`— dijo él —`), then speech again after the closing incise.
- Handle:
  - multi-paragraph quotes (open mark with no close continues into the next block that opens with a
    mark);
  - apostrophe versus closing ‘’ (reuse `_APOSTROPHE`);
  - nesting (inner quotes stay with the outer speaker).
- Table-driven pytest cases per language. This is the spec, so expected values come from the
  punctuation rules, not from current output.

### 2. Segmentation: `epub.process_xhtml_inplace`

- Find each sentence's span in `full_text_clean` (punkt returns substrings, located sequentially)
  and intersect it with the quote spans. Each segment dict gains:
  ```python
  {"id": "f000123", "text": <clean whole sentence>, "block": 57,
   "segments": [{"text": clean_text_for_tts(piece), "quote": "c03.b57.q0"}, {"text": "she said.", "quote": None}]}
  ```
  - `“Run,” she said.` gives `[("Run,", q), ("she said.", None)]`.
  - A quote crossing a sentence boundary keeps one `quote_id` across sentences.
- Drop segments that are empty or punctuation-only after cleaning. `clean_text_for_tts` turns `—`
  into `", "`, so strip leading and trailing commas per segment.
- **One `<span id>` per sentence is unchanged**, as is one `<par>` per sentence in the SMIL.
  Highlighting stays sentence-level; only the audio inside a clip changes voice. No XHTML or SMIL
  format change, so epubcheck and Storyteller behave as now.
- Return per-block text with quote markers for the attributor, e.g. `[Q12]“Run,”[/Q12] she said.`
  with chapter and block order. Turn-taking across paragraphs is the main signal for implicit
  quotes.
- Quote IDs are `<chapter name>.<block index>.<ordinal>`, stable for a given `book_sha` because
  wrapping is deterministic.

### 3. Attribution: new `src/calliope/attribution.py`

- **Interface:** `Attributor.attribute(book: BookText, roster_hint) -> SpeakerMap`.
- **Implementations:**
  - `LlamaServerAttributor`: spawns `llama-server -m MODEL.gguf -ngl 99 -c 8192 --port <random>
    --host 127.0.0.1`, waits for `/health`, and talks HTTP with stdlib `urllib` (no new Python
    deps). It terminates and waits for the server in `finally`. `--llm-url` uses an existing
    OpenAI-compatible server instead of spawning one.
  - `FileAttributor`: `--speakers FILE`, the reviewed or edited override.
  - `NullAttributor`: dialogue and single modes.
- **Roster pass:**
  - Per ~4k-token chunk: "list characters named or speaking: canonical name, aliases, gender
    m/f/x/unknown, age child/adult/elderly".
  - Merge entries by alias overlap, then run one consolidation prompt over the merged list.
- **Attribution pass:**
  - 4,096-token chunks with 1,024-token overlap (the Michel et al. setup). The prompt contains the
    roster (id, name, aliases) and the chunk with numbered quotes. The answer is `{"Q12": "c3",
    ...}` under a `json_schema` `response_format`, a flat object of string enums. llama.cpp's schema
    support has no `patternProperties`, so build an explicit `properties` list per chunk.
  - No chain-of-thought (generation is the slow part on a P4). Disable Qwen3 thinking.
  - Overlapping chunks: the later chunk wins, since it saw more preceding context.
- **Resumability:** each chunk response is cached at `<work>/attribution/<digest>.json`, where the
  digest covers `book_sha`, `model_sha`, `prompt_version` and the chunk text. pve2 stopping mid-pass
  loses at most one chunk. This matches the clip cache's write-JSON-last convention.
- **`<work>/speakers.json`** is written atomically once complete and is human-editable:
  ```json
  {"version": 1, "book_sha": "...", "attributor": "llama.cpp b<tag>:Qwen3-8B-Q4_K_M@<sha>:prompt-v1", "lang": "en",
   "characters": {"c1": {"name": "Elizabeth Bennet", "aliases": ["Lizzy", "Eliza"], "gender": "f", "age": "adult", "quotes": 412}},
   "quotes": {"c03.b57.q0": {"speaker": "c1", "text": "Run,"}}}
  ```
  - `text` is a short excerpt for review.
  - On load, quote IDs that are unknown or missing fall back to the unknown-speaker voice instead of
    failing.
- **Batch keeps the speakers file:** `calliope_batch.py` copies `speakers.json` next to the report
  in `readalouds/<collection>/<Title>/`.
  - Correcting a book: re-drop it with `Title.speakers.json` in the inbox, which becomes
    `--speakers`.
  - The batch script deletes `work/<Title>` on success, so a corrected re-run resynthesises
    everything. Keeping `work/` for N days would make it incremental.

### 4. TTS backend: `tts.py`

- `generate(text, seed, voice)`.
- `ChatterboxBackend.__init__(model, lang, device)` takes no single voice. It keeps `self._conds =
  {voice_path: Conditionals}`, built lazily with `model.prepare_conditionals(path)`, and swaps
  `self.model.conds` before each generate.
  - Conditionals are small. Chatterbox exposes `Conditionals.save/load`, and `generate()` just uses
    `self.conds`.
  - One model in VRAM serves every voice.
- `synthesize_sentence(backend, text, seed, voice)` is unchanged otherwise.
- `FakeBackend.generate(text, seed, voice)` derives its base frequency from `sha256(voice)`, so each
  voice sits in its own band (e.g. 150 + 100·k Hz). Tests can then verify a clip's voice from audio
  alone.

### 5. Cache keys: `cache.py`, `pipeline.py`

- `Sentence` gains `clips: [Clip(text, voice_name, voice_sha, key)]`. The key is unchanged:
  ```python
  clip_key(book_sha, clip.text, mid, lang, clip.voice_sha, settings)
  ```
- **Single-voice mode produces one clip with the whole sentence text and the narrator voice:
  identical keys to today**. Existing work dirs stay valid, so no `CACHE_VERSION` bump.
- Editing `speakers.json` or the cast only re-keys the segments whose voice changed. Narration
  segments (`she said.`) are shared and deduplicated across the book by key.
- Clip `meta` gains `"voice": name` (for tests and debugging).
- `unique`, `todo`, QA and retries operate on clips instead of sentences. `force_silence` and the
  report's `flagged` entries address clips (sentence index + segment index).
- **Assembly:**
  - Sentence wav = its clips with leading and trailing silence trimmed, joined with
    `SEGMENT_GAP_SECONDS` (~0.1 s, est.), then loudness-matched (`pyloudnorm` already ships with
    Chatterbox; numpy RMS for the fake backend).
  - `assemble_chapter` still gets one `(text_id, wav)` per sentence, so SMIL timing stays exact.
  - `chapter_path` digests the nested clip-key lists plus `segment_gap` and the loudness setting in
    `encoding`.
- **QA:** `evaluate()` per clip works as is (1 s slack covers short clips). Add a check for very
  short segments, e.g. under 3 characters, since one-word Chatterbox clips are a known risk; measure
  this.

### 6. CLI and sidecar

**CLI flags:**

| Flag | Meaning |
|---|---|
| `--voices DIR` | Library with `voices.json`; `--voice` stays the narrator |
| `--voice-mode single\|dialogue\|multi` | Default `single` |
| `--dialogue-voice NAME` | Voice for all quoted speech in dialogue mode |
| `--speakers FILE` | Skip attribution and use this map |
| `--cast FILE` / `--series-cast FILE` | Pinned voices; the series file is updated after success |
| `--llm-model PATH.gguf` | Or a pinned default, downloaded to `$HF_HOME` with a sha256 check |
| `--llm-url URL` | Use an external server; don't spawn one |
| `--llm-ctx 8192` | Context size |
| `--min-quotes 5` | Below this a character gets a minor voice |
| `--strict-voices` | Fail instead of falling back |

**Sidecar** (`Title.json`; `calliope_batch.options()` validates names against `safe_name` and maps
fields to flags):

```json
{"lang": "en", "voice": "default", "collection": "books",
 "voice_mode": "multi", "dialogue_voice": "f1", "series": "discworld",
 "cast": {"Granny Weatherwax": "f_old"}}
```

### 7. Failure behaviour

Degrade, don't fail, unless `--strict-voices` is set: multi → dialogue → single.

- **Attribution fails:** e.g. `llama-server` won't start, CUDA OOM, timeout, or schema-invalid JSON
  after 2 retries per chunk.
  - One chunk failing: only that chunk's quotes go to the unknown-speaker voice.
  - Over 20% of chunks failing, or the roster pass failing: the whole book drops to dialogue mode.
- **Quote detection finds nothing** (unusual punctuation): single voice.
- **Voice library missing or invalid:** single voice.
- **Report:** `"voices": {"requested": "multi", "used": "dialogue", "reason": "...", "cast":
  {...}}`. Exit code 0.
- **Batch:** `calliope_batch.py` adds "(fell back to dialogue voice)" to the ntfy message.

### 8. Tests (fake backend, no GPU)

- `epub_factory` gets a dialogue chapter:
  - en: `“Run,” she said.`, plus a two-sentence quote and a multi-paragraph quote;
  - de: `„…“`;
  - es: dash dialogue.
- Integration tests through `run_cli`:
  - Dialogue mode: the quote clip's meta voice and FFT band match the dialogue voice, and the tag's
    match the narrator's. Exactly one `<par>` per sentence. Overlay duration equals audio duration
    (existing asserts). epubcheck passes.
  - `--speakers` fixture with two characters: each gets the expected voice. Editing one quote's
    speaker and rerunning gives `synthesized == 1`.
  - Single mode produces **byte-identical output and the same clip keys as before the change**
    (regression guard against cache churn).
  - LLM path against a stub OpenAI-compatible `http.server` in a thread, via `--llm-url`: chunking,
    overlap merge, caching (a rerun makes 0 requests), and fallback on garbage JSON, an HTTP 500 or
    a timeout. The report says `used: dialogue`. Exit 0.
  - SIGTERM mid-attribution, then resume: no repeated chunk requests (extends `test_sigterm_...`).
  - `quotes.py` table tests per language. `assign_voices` tests: determinism, gender match, pool
    exhaustion to minor voices, series cast reuse.
- An opt-in accuracy eval (not in CI): a script over a PDNC subset (gold quotes and speakers) and
  one hand-labelled chapter per main non-English language. Use it to choose the model, prompt and
  `--min-quotes`.

### 9. Container and dependencies

- **Containerfile:** add a build stage `FROM nvidia/cuda:12.4.1-devel-ubuntu22.04`. Build a **pinned
  llama.cpp release tag** with:
  ```
  -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61 -DGGML_NATIVE=OFF -DLLAMA_CURL=OFF
  ```
  Copy `llama-server` and `libggml*.so`/`libllama.so` into the runtime image. The runtime base
  already has cuBLAS.
  - Image growth is ~50–150 MB (est., single architecture).
  - No new Python packages: HTTP via stdlib.
- **Why not the official image:** `ghcr.io/ggml-org/llama.cpp:server-cuda` builds CUDA 12.8.1, where
  Pascal is only `61-virtual` PTX (JIT on first load). llama.cpp drops Pascal for CUDA ≥13 builds,
  so tag drift would break the P4. A second container would also make sequential GPU handoff a
  cross-unit problem.
- **Model:** the GGUF (~5 GB) goes on the existing `/cache` volume, pinned by HF repo, revision and
  sha256. Excluded from backups, like the Chatterbox weights.
- **Quadlet:** no change beyond the new sidecar fields and a `casts/` dir under
  `/srv/media/books/narrate` (already mounted).
- **Host RAM:** with full GPU offload `llama-server` mmaps the GGUF (~5 GB page cache, about 1 GB
  resident, est.). The websvcs VM's vCPU and RAM sizing isn't documented. pve2 is an i5-13500
  (6P+8E) with 32 GB DDR5 shared with the gaming and devtop VMs and pbs2 (`docs/architecture.md`).
- **CPU fallback:** without a GPU, llama.cpp would take several hours per novel (est.). Acceptable
  for batch, but default to dialogue mode when CUDA is unavailable.

## Effort and risks

**Effort** (est., focused dev-days):

| Work | Days |
|---|---|
| `quotes.py` (10 languages) + segmentation + multi-voice backend + clip-level cache and assembly + dialogue mode + tests | 4–5 |
| LLM attributor (server lifecycle, roster and attribution prompts, chunk cache, schema, fallback, stub-server tests) | 4–6 |
| Voice manifest, assignment, series cast, sidecar and `calliope_batch.py` wiring, report | 2–3 |
| Containerfile llama.cpp stage + P4 measurement (VRAM, tok/s, minutes per novel) | 1–2 |
| Accuracy eval harness (PDNC subset, hand-labelled non-English chapter) | 2–3 |
| **Total** | **~13–19 days**; dialogue mode alone is ~4–5 |

**Risks:**

- **Accuracy:**
  - Published numbers assume a gold character list. With an LLM-built roster, expect roughly 1 quote
    in 8–10 misattributed (est.). Mitigation: distinct voices only for top characters; unknown goes
    to the narrator.
  - Non-English accuracy is unmeasured anywhere. Dash dialogue makes quote detection itself harder.
- **Audio quality:**
  - Chatterbox on very short segments ("Run,", "No!") may truncate, ramble or add artifacts. QA
    retries help; measure on a real book.
  - Voices differing in loudness or room tone mid-sentence: trim and loudness-match at assembly, and
    record reference WAVs under similar conditions.
- **Time:** more and shorter clips mean more per-call overhead. Expect +20–40% TTS time in
  dialogue-heavy books (est.).
- **Platform drift:** Pascal is losing support (CUDA 13; PyTorch after 2.14; Ollama runner churn).
  Pin the llama.cpp tag and CUDA 12.4 like the rest of the image.
- **Licensing:**
  - Qwen3 is Apache-2.0 and llama.cpp is MIT. ModernBookNLP has no license (don't vendor it). Llama
    3.x has its own community license.
  - Voice reference WAVs need consent or a public-domain source (e.g. LibriVox readers' terms).
- **Edits cost a full re-render**, because the batch deletes `work/` on success.

## Sources

- **Calliope code** (fork, branch `main`):
  - `src/calliope/epub.py`: `process_xhtml_inplace`,
    `clean_text_for_tts`, `_QUOTES`
  - `src/calliope/pipeline.py`: `run`, `_prepare_book`, lazy
    `make_backend`
  - `src/calliope/tts.py`:
    `ChatterboxBackend.prepare_conditionals`, `FakeBackend`
  - `src/calliope/cache.py`: `clip_key`
  - `Containerfile`
  - `pyproject.toml`
  - `uv.lock`: transformers 5.2.0
- **Homelab:**
  - `planning/narrated-ebooks/spec.md`
  - `planning/narrated-ebooks/issues/02-deploy-calliope-websvcs.md`
  - `src/services/calliope/calliope_batch.py`
  - `src/services/calliope/calliope.container.j2`
  - `docs/guides/gpu.md` (driver 580)
  - `docs/architecture.md` (pve2 hardware) and `docs/services.md` (wyoming
    whisper not in use)
- **Chatterbox Turbo conditionals:**
  https://github.com/resemble-ai/chatterbox/blob/master/src/chatterbox/tts_turbo.py
- **Michel, Epure, Hennequin, Cerisara**, "Evaluating LLMs for Quotation Attribution in Literary
  Texts: A Case Study of LLaMa3", NAACL 2025: https://arxiv.org/abs/2406.11380 (results:
  https://arxiv.org/html/2406.11380v3)
- **Michel, Attali, Epure**, "Fast and Accurate Quotation Attribution in Literary Texts", Aug 2026:
  https://arxiv.org/abs/2608.02359; code (ModernBookNLP, no license):
  https://github.com/gasmichel/ModernBookNLP_QA
- **PDNC:** https://arxiv.org/abs/2204.05836; BookNLP vs BookNLP+ on PDNC:
  https://arxiv.org/html/2307.03734v1
- **Character embeddings for quote attribution:** https://arxiv.org/abs/2406.11368
- **BookNLP:** https://github.com/booknlp/booknlp
- **Muzny et al. 2017**, two-stage sieve: https://aclanthology.org/E17-1044/
- **Chinese:** SIG https://arxiv.org/pdf/2312.14590; CSI
  https://aclanthology.org/2022.naacl-main.165
- **German direct speech:** https://dh-abstracts.library.virginia.edu/works/11925
- **BookNLP-fr / multilingual BookNLP:**
  https://odhn.ens.psl.eu/en/article/booknlp-french-part-multilingual-booknlp-project
- **llama.cpp:**
  - Default CUDA architectures (61-virtual only for CUDA <13):
    https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cuda/CMakeLists.txt
  - Official CUDA image (12.8.1):
    https://github.com/ggml-org/llama.cpp/blob/master/.devops/cuda.Dockerfile
  - JSON schema and grammar limits:
    https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md
  - P40 (sm_61) reports: https://github.com/ggml-org/llama.cpp/discussions/25978
- **Ollama GPU support (compute capability 6.1):** https://docs.ollama.com/gpu
- **PyTorch dropping Pascal after CUDA 12.x wheels end:**
  https://dev-discuss.pytorch.org/t/notice-cuda-12-6-wheels-will-no-longer-be-published-from-pytorch-2-15-drops-maxwell-pascal-volta/3432
- **Multi-voice projects:**
  - https://github.com/prakharsr/audiobook-creator
  - https://github.com/Finrandojin/alexandria-audiobook
  - https://github.com/DrewThomasson/VoxNovel
  - https://github.com/lukaszliniewicz/Pandrator
  - https://github.com/DrewThomasson/ebook2audiobook
  - https://github.com/aedocw/epub2tts
- **Unverified:**
  - P4 tok/s (no published measurement).
  - Qwen3 and Gemma language counts and GGUF sizes (vendor figures from memory).
  - Ollama v0.32 CUDA 12 runner details (secondary source:
    https://localaimaster.com/blog/pascal-gpus-after-cuda-13).
