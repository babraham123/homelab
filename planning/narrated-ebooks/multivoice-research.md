# Multi-voice narration for Calliope: speaker attribution research and design

Research for 06 and 07, 2026-10-11; how to run Qwen3-8B added 2026-10-12. (est.) marks estimates
that are neither sourced nor measured on the P4. The maintainer chose to run everything on the P4 (no
RTX 3060 Ti) and to narrate articles in a single voice.

## Recommendation

1. **Quote detection: rule-based, per language, inside Calliope.** It is deterministic, testable,
   and gives exact character offsets. The offsets are needed to split sentences, and an LLM can't be
   trusted to return them.
2. **Speaker attribution: a local LLM through `llama-server` (llama.cpp)**, built for sm_61 on CUDA
   12.4 inside the Calliope image.
   - Model: **Qwen3-8B Q4_K_M** (Apache-2.0, multilingual). Benchmark it against
     Qwen3-4B-Instruct-2507 before pinning one.
   - Rules first: per-language speech-verb rules lock the explicitly tagged quotes (`“Run,” said
     Elizabeth`), where rules beat the LLM (BookNLP+ 98.6% vs Llama-3-8B 92.8–94.7% on explicit
     quotes). The LLM sees them as already labelled context.
   - Then the LLM, greedy, thinking off, JSON constrained by a schema:
     - **Roster pass:** characters with aliases, gender and age.
     - **Attribution pass:** 8k-token chapter-bounded windows; each labels only its central 4k, so
       every quote gets one prediction with context on both sides. Answers are canonical names.
     - **Re-pass:** quotes whose renormalised probability is under ~0.6 (est.) are asked again with
       thinking on; still unsure, they get the dialogue voice.
   - This is the only approach that covers all ten languages with one code path. It is also the
     published LLM state of the art in this size class: Llama-3-8B scores 88.5–90.6% on PDNC given a
     gold character list. The authors call that an upper bound; no figure exists for an LLM-built
     roster.
3. **It runs as a separate phase before TTS, in the same `calliope` process.** The LLM (~6.8 GB with
   a 12k q8_0 cache, est.) and Chatterbox (fp32, ~3–4 GB, est.) don't fit together in the P4's 8 GB.
   Calliope already loads the TTS model lazily after `_prepare_book`, so attribution slots in
   between, and its subprocess exits (freeing VRAM) before Chatterbox loads. The wyoming whisper
   quadlet is "not in use" (`docs/services.md`), so nothing else contends for the GPU.
4. **Cost:** about 35 min of P4 time for Pride and Prejudice plus 20–40 min of re-pass (est.,
   [Running Qwen3-8B](#running-qwen3-8b-on-the-p4)), against an estimated 10–25 h of TTS. That's
   under 10% overhead.
5. **Build the cheap mode first:** a dialogue voice (all quoted speech in one alternate voice, no
   character tracking). It needs the same segmentation, multi-voice backend and cache changes, but
   no ML. Multi-voice is then an attributor plugged into a working pipeline.
6. **Not now:**
   - BookNLP: 0.40 accuracy on PDNC and English only.
   - ModernBookNLP_QA: 92–94.5% on PDNC, English only, no license, 2 commits, and pins transformers
     4.57 against Chatterbox's 5.2. Revisit as an English-only attribution backend once it has a
     license. Until then it is the English accuracy bar in 07's evaluation, run in a throwaway venv.
   - Qwen3.5-9B (Apache-2.0): a smaller KV cache per token would allow 16–32k windows, but llama.cpp
     reprocesses prompts for hybrid models (#24587), it has no `/no_think` switch, and its speed on
     Pascal is unmeasured. Revisit once the bug is fixed.
   - Fine-tuning Qwen3-8B on PDNC (CC-BY 4.0): needs a rented 24 GB GPU (the P4 has no tensor cores),
     English training data only, and no published fine-tuned LLM result to aim for.
   - Cloud LLMs: the API is OpenAI-compatible, so `--llm-url` could point at one, but the whole book
     text would leave the house (~200k input tokens per novel). Off by default.

## Comparison

| Approach | Accuracy (PDNC, English) | Non-English | P4 fit / time per novel | License / maturity | Verdict |
| --- | --- | --- | --- | --- | --- |
| Rule-based sieve (Muzny 2017) | F 87.5 on 3 novels; precision 90.4 at recall 65.1 in high-precision mode; collapses on implicit quotes | Rules per language; none published for da/no/sv etc. | CPU, seconds | Easy to write | Use for **quote detection** and to lock **explicit** quotes (speech verb next to a name); the LLM does the rest |
| BookNLP (original, big/small) | 0.40 on PDNC (0.28 on implicit); B3 89.9/86.4 on its own data | English only | ~2–5 min on GPU or CPU | MIT; dormant since 2024; old transformers | Reject |
| BookNLP+ (retrained on PDNC) | 78.5 / 79.2 | English only | Minutes | Research code | Reject |
| ModernBookNLP_QA (Michel et al., Aug 2026) | **94.5** joint (9.2 GB VRAM); **92.3** direct (2.4 GB); assumes a character list | English only (ModernBERT) | Fits (direct variant); seconds | **No license**, 2 commits, transformers 4.57 pin | Future English upgrade, in its own venv |
| Llama-3-8B, 8-bit, gold character list (Michel et al., NAACL 2025) | **90.6** (PDNC1), 88.5 (PDNC2); explicit quotes 92.8–94.7; ChatGPT ~71 | Untested; model-dependent | 14 GB at 8-bit; 10–60 min on A5000 | Llama license | Method to copy; one calibration run in 07 |
| **Qwen3-8B Q4_K_M via llama.cpp** (recommended) | Not published; expect high 80s for English with an LLM-built roster (est.) | Qwen3 claims 119 languages, covers all ten | 5.03 GB weights + 0.9 GB q8_0 KV at 12k ctx; ~35 min + 20–40 min re-pass for P&P (est.) | Apache-2.0; llama.cpp MIT | **Use** |
| Qwen3.5-9B Q4_K_M | Not published | 201 languages | 5.68 GB; ~32 KiB KV/token allows 16–32k windows; Pascal speed unknown | Apache-2.0 | Later: llama.cpp hybrid-model prompt-cache bug |
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
  5. Unknown, `_other` and still-low-confidence speakers get the dialogue voice, or the narrator's
     when none is set. A neutral voice is less jarring than a wrong character's voice.
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

```text
_prepare_book    -> chapters -> sentences, each with segments [(text, quote_id|None)]; blocks with quote spans
attribute()      -> speakers.json: sieve, roster, windows, re-pass (cached; skipped when mode is single or dialogue)
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
  | --- | --- |
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
- Fragments of one utterance split by a speech tag in the same paragraph (`“Run,” she said, “now.”`)
  share one quote ID, so they are attributed once.
- Quote IDs are `<chapter name>.<block index>.<ordinal>`, stable for a given `book_sha` because
  wrapping is deterministic.

### 3. Attribution: new `src/calliope/attribution.py`

- **Interface:** `Attributor.attribute(book: BookText, roster_hint) -> SpeakerMap`.
- **Implementations:**
  - `LlamaServerAttributor`: spawns `llama-server` on `127.0.0.1:<random>` with the flags in
    [Running Qwen3-8B](#running-qwen3-8b-on-the-p4), waits for `/health`, and talks HTTP with stdlib
    `urllib` (no new Python deps). It terminates and waits for the server in `finally`. `--llm-url`
    uses an existing OpenAI-compatible server instead of spawning one.
  - `FileAttributor`: `--speakers FILE`, the reviewed or edited override.
  - `NullAttributor`: dialogue and single modes.
- **1. Explicit sieve (rules, no LLM):** per-language speech-verb lists (`said`, `sagte`, `dijo`,
  `dit`, `sa`...) and patterns: quote, then verb and name or alias in either order, in the same
  paragraph; or a dash incise naming the speaker. These labels are locked. Muzny et al.'s sieve
  ordering is the model. Pronoun tags (`she said`) are left to the LLM.
- **2. Roster pass:**
  - English: seed names and genders from BookNLP's character clusters is an option once the
    head-to-head has it installed (est.); otherwise the same path as other languages.
  - Per ~4k-token chunk: "list characters named or speaking: canonical name, aliases, gender
    m/f/x/unknown, age child/adult/elderly, one evidence sentence".
  - Auto-merge only identical full names. Shared surnames, titles and first names (Mr. and Mrs.
    Bennet; "Mrs. Collins" is Charlotte Lucas; "Fitzwilliam" is Darcy and the Colonel) go to one
    consolidation prompt that sees each entry's evidence.
  - The roster is frozen before attribution, so the prompt prefix stays byte-identical.
- **3. Attribution pass:**
  - Windows of 8k text tokens that never cross a chapter; a short chapter is one window. Each
    window labels only the quotes in its central 4k; the 2k on each side is context, so every quote
    gets exactly one prediction with context on both sides. Michel et al. used 4k chunks at a 1k
    stride (3k overlap) and resolved overlaps by re-prompting with earlier answers (88.5) rather
    than keeping the first (87.6); one centred prediction gets most of that more cheaply (est.).
  - Quotes already labelled (sieve, or an earlier window) appear as `[Q101=Elizabeth Bennet]` and
    are not asked again.
  - Answers are **canonical names**, not `c3`: `{"Q105": "Elizabeth Bennet", ...}` under a
    `json_schema` `response_format`. Each key's `enum` is the main characters, those named in the
    window, and `_other` (servant, crowd, unnamed). llama.cpp's schema support has no
    `patternProperties`, so build explicit `properties`, **and list every key in `required`**: an
    unlisted key is optional in the generated grammar and the model can skip it. Unsupported schema
    features are dropped silently.
  - Greedy, no chain-of-thought, Qwen3 thinking off. Qwen3-8B scores lower on RULER with thinking on
    (94.4 vs 96.0 at 8k), and thinking everywhere would add 2–3 h per novel (est.).
- **4. Confidence:** request `logprobs` with `top_logprobs: 10`. llama.cpp reports them from the raw
  softmax before the grammar applies, so for each answer take the first token where the candidate
  names differ and renormalise over the candidates' tokens. Not `post_sampling_probs`: the grammar
  only acts after a sampled token is rejected, so those figures are inconsistent.
- **5. Re-pass:** quotes under τ ≈ 0.6 (est., tuned on PDNC) are batched per window and asked again
  in a ~2k-token window with thinking on (`thinking_budget_tokens: 512`, temperature 0.6, top_p
  0.95, top_k 20, Qwen's thinking settings). Still under τ: unknown speaker.
- **6. Post-processing:** in an untagged two-person exchange speakers should alternate; a violation
  is flagged in the report for review, not overwritten.
- **Resumability:** each window's response (and each re-pass batch) is cached at
  `<work>/attribution/<digest>.json`, where the digest covers `book_sha`, `model_sha`,
  `prompt_version`, the roster and the window text. pve2 stopping mid-pass loses at most one window.
  This matches the clip cache's write-JSON-last convention.
- **`<work>/speakers.json`** is written atomically once complete and is human-editable:

  ```json
  {"version": 1, "book_sha": "...", "attributor": "llama.cpp b<tag>:Qwen3-8B-Q4_K_M@<sha>:prompt-v1", "lang": "en",
   "characters": {"c1": {"name": "Elizabeth Bennet", "aliases": ["Lizzy", "Eliza"], "gender": "f", "age": "adult", "quotes": 412}},
   "quotes": {"c03.b57.q0": {"speaker": "c1", "text": "Run,", "source": "llm", "p": 0.93}}}
  ```

  - `text` is a short excerpt for review; `source` is `sieve`, `llm`, `repass` or `edit`, and `p`
    the renormalised probability, so a reviewer can sort by doubt.
  - On load, quote IDs that are unknown or missing fall back to the unknown-speaker voice instead of
    failing.
- **Batch keeps the speakers file:** `calliope_batch.py` copies `speakers.json` next to the report
  in `readalouds/<collection>/<Title>/`.
  - Correcting a book: re-drop it with `Title.speakers.json` in the inbox, which becomes
    `--speakers`.
  - The batch script deletes `work/<Title>` on success, so a corrected re-run resynthesises
    everything. Keeping `work/` for N days would make it incremental.

### Running Qwen3-8B on the P4

**Server:**

```bash
llama-server -m Qwen3-8B-Q4_K_M.gguf --host 127.0.0.1 --port <random>
  -ngl 99 -c 12288 -np 1 -fa on -ctk q8_0 -ctv q8_0 --jinja
  --temp 0 --repeat-penalty 1.0 --presence-penalty 0
```

- `--jinja` applies Qwen3's chat template, which reads `enable_thinking`.
- `-fa on` works on Pascal (+~3% prompt speed) and is required for a quantised V cache.
- `-np 1`: one slot, so the cached prefix is never evicted by another request.
- Penalties off, set explicitly: the server docs disagree on the `repeat_penalty` default (1.1 vs
  1.0), and the Qwen GGUF card's `presence_penalty` 1.5 for quantised models would push the model
  away from the speaker names it must repeat.

**Request** (`/v1/chat/completions`):

```json
{"messages": [{"role": "system", "content": "<SYSTEM>"}, {"role": "user", "content": "<USER>"}],
 "chat_template_kwargs": {"enable_thinking": false},
 "temperature": 0, "repeat_penalty": 1.0, "presence_penalty": 0,
 "logprobs": true, "top_logprobs": 10, "cache_prompt": true, "max_tokens": "<10 * quotes + 32>",
 "response_format": {"type": "json_schema", "json_schema": {"name": "attr", "schema": {
   "type": "object", "additionalProperties": false,
   "properties": {"Q105": {"enum": ["Elizabeth Bennet", "Mr. Darcy", "Jane Bennet", "_other"]}},
   "required": ["Q105"]}}}}
```

**Prompt.** The system message is the same for every window of a book, so llama-server reuses its
KV cache as a prefix (~2k of ~10k tokens, ~20% of prompt work, est.). The passage goes last, after
everything static. Inline markers follow Michel et al.'s published prompts, which keep context that
a separate list of quotes loses.

```text
SYSTEM:
You identify who speaks each marked quotation in a novel excerpt.
Characters (canonical name: aliases; gender):
Elizabeth Bennet: Lizzy, Eliza, Miss Eliza; f
...
_other: any speaker not listed (servant, crowd, unnamed).
Quotes are marked [Qn]…[/Qn]. [Qn=Name]… is already attributed; use it as context.
The speaker utters the words; not the addressee or a person mentioned.
In untagged exchanges, speakers usually alternate.
Return JSON mapping each requested ID to one name from the list. No explanation.
<two short examples in the book's language and quote style: « » for fr, „“ for de, dashes for es>

USER:
Excerpt (Chapter 12):
<<< …[Q101=Elizabeth Bennet]“…”… [Q105]“…”[/Q105] said she … >>>
Label: Q105, Q106, …, Q131
```

**Memory** (Qwen3-8B: 36 layers, 8 KV heads, head dim 128, so 144 KiB per token at f16):

| Context | KV f16 | KV q8_0 |
| --- | --- | --- |
| 8k | 1.13 GiB | 0.60 GiB |
| 12k | 1.69 GiB | 0.90 GiB |
| 16k | 2.25 GiB | 1.20 GiB |

- Q4_K_M (5.03 GB) at 12k q8_0 is ~6.8 GB with compute buffers (est.): fits.
- Q5_K_M (5.85 GB) at 12k is ~7.6 GB (est.): tight; worth one A/B on PDNC. Unsloth's UD-Q4_K_XL
  (5.14 GB) is the other A/B. Q6_K and Q8_0 leave no room for useful context.
- Qwen3-4B-Instruct-2507 has the same KV per token (36 layers, 8 KV heads); it saves weights only.
- Windows stay at 8k text + ~2k prompt: Qwen3-8B holds 96.0 on RULER at 8k but drops to 91.8 at 16k.

**Speed:** the one P4 measurement is Llama-2-7B Q4_0 with flash attention: 529 t/s prompt, 33 t/s
generation (llama.cpp #15013). Scaled to Qwen3-8B Q4_K_M: ~300–380 and ~18–22 t/s (est.). Pride and
Prejudice (~160k tokens, 1,270 quotes: 637 implicit, 327 explicit, 306 anaphoric):

| Phase | Work | Time (est.) |
| --- | --- | --- |
| Roster | ~40 chunks | ~10 min |
| Attribution | ~330k prompt tokens, ~10k output | ~16 + 9 min |
| Re-pass | ~10% of quotes, thinking on | 20–40 min |

Grammar-forced tokens (keys, punctuation, the rest of a name) are still decoded one at a time, so
each answer costs ~8 steps (est.).

**Pinned weights:** `Qwen/Qwen3-8B-GGUF` revision `7c41481` (`Qwen3-8B-Q4_K_M.gguf`), sha256 recorded
at pin time; A/B `unsloth/Qwen3-8B-GGUF` revision `a6adef1` (`UD-Q4_K_XL`).

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
| --- | --- |
| `--voices DIR` | Library with `voices.json`; `--voice` stays the narrator |
| `--voice-mode single\|dialogue\|multi` | Default `single` |
| `--dialogue-voice NAME` | Voice for all quoted speech in dialogue mode |
| `--speakers FILE` | Skip attribution and use this map |
| `--cast FILE` / `--series-cast FILE` | Pinned voices; the series file is updated after success |
| `--llm-model PATH.gguf` | Or a pinned default, downloaded to `$HF_HOME` with a sha256 check |
| `--llm-url URL` | Use an external server; don't spawn one |
| `--llm-ctx 12288` | Context size: 8k window + prompt |
| `--min-confidence 0.6` | Below this a quote is re-asked with thinking, then gets the unknown voice |
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
  - One window failing: only its quotes go to the unknown-speaker voice (sieve labels stand).
  - Over 20% of windows failing, or the roster pass failing: the whole book drops to dialogue mode.
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
  - LLM path against a stub OpenAI-compatible `http.server` in a thread, via `--llm-url`:
    - windows never cross a chapter, and every quote is asked exactly once, in the window whose
      core holds it;
    - sieve-labelled quotes are sent as `[Qn=Name]` and never asked;
    - every asked ID is in the schema's `required`, and the system message is byte-identical across
      windows;
    - stub logprobs under `--min-confidence` trigger one re-pass request with thinking on; still
      low gives the unknown voice;
    - caching (a rerun makes 0 requests), and fallback on garbage JSON, an HTTP 500 or a timeout.
      The report says `used: dialogue`. Exit 0.
  - SIGTERM mid-attribution, then resume: no repeated window requests (extends `test_sigterm_...`).
  - `quotes.py` and sieve table tests per language. `assign_voices` tests: determinism, gender
    match, pool exhaustion to minor voices, series cast reuse. Roster merge: Mr./Mrs. Bennet and a
    shared first name stay separate.
- An opt-in accuracy eval (not in CI): a script over PDNC novels (gold quotes and speakers) and one
  hand-labelled chapter per main non-English language. It scores all, explicit, implicit and
  anaphoric quotes separately. Use it to choose the model, quant, prompt, `--min-confidence` and
  `--min-quotes`. Pride and Prejudice is probably memorised by LLMs, so also score a less famous
  PDNC novel.

### 9. Container and dependencies

- **Containerfile:** add a build stage `FROM nvidia/cuda:12.4.1-devel-ubuntu22.04`. Build a **pinned
  llama.cpp release tag** with:

  ```text
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
| --- | --- |
| `quotes.py` (10 languages) + segmentation + multi-voice backend + clip-level cache and assembly + dialogue mode + tests | 4–5 |
| LLM attributor (server lifecycle, sieve, roster and attribution prompts, windows, confidence and re-pass, cache, schema, fallback, stub-server tests) | 6–8 |
| Voice manifest, assignment, series cast, sidecar and `calliope_batch.py` wiring, report | 2–3 |
| Containerfile llama.cpp stage + P4 measurement (VRAM, tok/s, minutes per novel) | 1–2 |
| Accuracy eval harness (PDNC subset, hand-labelled non-English chapter) | 2–3 |
| **Total** | **~15–21 days**; dialogue mode alone is ~4–5 |

**Risks:**

- **Accuracy:**
  - Published numbers assume a gold character list. With an LLM-built roster, expect roughly 1 quote
    in 8–10 misattributed (est.). Mitigation: sieve labels for explicit quotes, a confidence
    re-pass, distinct voices only for top characters, and the dialogue voice for anything unsure.
  - Non-English accuracy is unmeasured anywhere. Dash dialogue makes quote detection itself harder.
- **Audio quality:**
  - Chatterbox on very short segments ("Run,", "No!") may truncate, ramble or add artifacts. QA
    retries help; measure on a real book.
  - Voices differing in loudness or room tone mid-sentence: trim and loudness-match at assembly, and
    record reference WAVs under similar conditions.
- **Time:** more and shorter clips mean more per-call overhead. Expect +20–40% TTS time in
  dialogue-heavy books (est.).
- **Platform drift:** Pascal is losing support (CUDA 13 removed it; PyTorch after 2.14; Ollama
  runner churn). Pin the llama.cpp tag and CUDA 12.4 like the rest of the image, and never let the
  build stage's base image float to CUDA 13.
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
  <https://github.com/resemble-ai/chatterbox/blob/master/src/chatterbox/tts_turbo.py>
- **Michel, Epure, Hennequin, Cerisara**, "Evaluating LLMs for Quotation Attribution in Literary
  Texts: A Case Study of LLaMa3", NAACL 2025: <https://arxiv.org/abs/2406.11380> (results and
  Appendix A chunking: <https://arxiv.org/html/2406.11380v3>; prompts:
  <https://github.com/deezer/llms_quotation_attribution/tree/main/prompts>)
- **Michel, Attali, Epure**, "Fast and Accurate Quotation Attribution in Literary Texts", Aug 2026:
  <https://arxiv.org/abs/2608.02359>; code (ModernBookNLP, no license):
  <https://github.com/gasmichel/ModernBookNLP_QA>
- **PDNC:** <https://arxiv.org/abs/2204.05836>; data (CC-BY 4.0, quote types, `character_info.csv`):
  <https://github.com/Priya22/project-dialogism-novel-corpus>; BookNLP vs BookNLP+ on PDNC:
  <https://arxiv.org/html/2307.03734v1>
- **Qwen3:** model card <https://huggingface.co/Qwen/Qwen3-8B>; GGUFs
  <https://huggingface.co/Qwen/Qwen3-8B-GGUF> and <https://huggingface.co/unsloth/Qwen3-8B-GGUF>;
  technical report with RULER by context and thinking mode (Table 23):
  <https://arxiv.org/html/2505.09388>; Qwen3.5-9B <https://huggingface.co/Qwen/Qwen3.5-9B>
- **Format constraints vs accuracy** ("Let Me Speak Freely"; constraints hurt reasoning, can help
  classification): <https://aclanthology.org/2024.emnlp-industry.91/>
- **Character embeddings for quote attribution:** <https://arxiv.org/abs/2406.11368>
- **BookNLP:** <https://github.com/booknlp/booknlp>
- **Muzny et al. 2017**, two-stage sieve: <https://aclanthology.org/E17-1044/>
- **Chinese:** SIG <https://arxiv.org/pdf/2312.14590>; CSI
  <https://aclanthology.org/2022.naacl-main.165>
- **German direct speech:** <https://dh-abstracts.library.virginia.edu/works/11925>
- **BookNLP-fr / multilingual BookNLP:**
  <https://odhn.ens.psl.eu/en/article/booknlp-french-part-multilingual-booknlp-project>
- **llama.cpp:**
  - Default CUDA architectures (61-virtual only for CUDA <13):
    <https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cuda/CMakeLists.txt>
  - Official CUDA image (12.8.1):
    <https://github.com/ggml-org/llama.cpp/blob/master/.devops/cuda.Dockerfile>
  - JSON schema and grammar limits (`required`, dropped features):
    <https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md>
  - Server parameters (`chat_template_kwargs`, `cache_prompt`, `n_probs`):
    <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>; logprobs taken before
    the grammar (`need_pre_sample_logits`):
    <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/server-context.cpp> and
    <https://github.com/ggml-org/llama.cpp/blob/master/common/sampling.cpp>
  - P4 benchmark (pp512 529 t/s, tg128 33 t/s, Llama-2-7B Q4_0):
    <https://github.com/ggml-org/llama.cpp/discussions/15013>
  - P40 (sm_61) reports: <https://github.com/ggml-org/llama.cpp/discussions/25978>
  - Hybrid-model prompt-cache reprocessing: <https://github.com/ggml-org/llama.cpp/issues/24587>
- **CUDA 13 drops Pascal:** <https://docs.nvidia.com/cuda/cuda-features-archive/index.html>
- **Ollama GPU support (compute capability 6.1):** <https://docs.ollama.com/gpu>
- **PyTorch dropping Pascal after CUDA 12.x wheels end:**
  <https://dev-discuss.pytorch.org/t/notice-cuda-12-6-wheels-will-no-longer-be-published-from-pytorch-2-15-drops-maxwell-pascal-volta/3432>
- **Multi-voice projects:**
  - <https://github.com/prakharsr/audiobook-creator>
  - <https://github.com/Finrandojin/alexandria-audiobook>
  - <https://github.com/DrewThomasson/VoxNovel>
  - <https://github.com/lukaszliniewicz/Pandrator>
  - <https://github.com/DrewThomasson/ebook2audiobook>
  - <https://github.com/aedocw/epub2tts>
- **Unverified:**
  - Qwen3-8B tok/s on the P4 (scaled from the Llama-2-7B measurement).
  - The confidence threshold, the centred-window gain and the BookNLP roster seed (no measurement).
  - Gemma language counts (vendor figures from memory).
  - Ollama v0.32 CUDA 12 runner details (secondary source:
    <https://localaimaster.com/blog/pascal-gpus-after-cuda-13>).
