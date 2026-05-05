# gemma-on-vm — PLAN.md

**Suite:** Software | **Client:** Lieutenant | **Started:** 2026-05-05
**Repo:** `~/continental/software/cases/gemma-on-vm/`
**Status:** Phase 1 (Whisper installs) substantially complete; Phase 2 (Gemma) deferred.

---

## Scope

Install, run, and verify local AI models on the Continental VM (Apple M3 Max paravirtualised under UTM, 8 cores, 64 GiB RAM, 112 GiB free disk). The contract covers two model families:

1. **Whisper** — audio → text / translate; multiple distributions
2. **Gemma** — text + multimodal LLM; planned for a later phase

Originally Gemma-only. Scope broadened 2026-05-05 after the Lieutenant supplied a 14-second WAV (`demo-audio-for-gemma.wav`, 48 kHz mono PCM) and asked for VM-side audio→translation today. Research found Whisper Large-v3 outperforms Gemma 4 E4B for raw transcription/translation accuracy. One contract covers both — sister ADRs **001a** (Whisper variant) and **001b** (Gemma variant).

Routing chosen: option **(I)** — extend the contract rather than open a sibling.

---

## Phases

### Phase 0 — Reconnaissance ✅ COMPLETE

- VM resource picture verified (M3 Max paravirtualised, 8 cores, 64 GiB RAM, 112 GiB free).
- Egress confirmed (HF 0.1 s, GitHub ~10 s — slow but reachable).
- Metal probe initial signal: empty (`system_profiler SPDisplaysDataType` returned nothing).
- Metal definitively confirmed at runtime in Phase 1 (whisper.cpp): `Apple Paravirtual device`, `MTL0 backend`.

### Phase 1 — Whisper installs ✅ SUBSTANTIALLY COMPLETE

**Goal:** install all 5 free Whisper distributions with `large-v3`-class models, smoke-test each, build a comparison harness so the Lieutenant can run failing-input tests.

| # | Backend | Install | Smoke (translate) | Wall (warm) | Notes |
|---|---|---|---|---:|---|
| 1 | **openai-whisper** (PyTorch) | ✅ | ✅ | 42.79 s | Reference; CPU only |
| 2 | **mlx-whisper** (MLX/Metal) | ✅ | ✅ | **3.74 s** | Fastest warm; weights cached |
| 3 | **whisperX** (faster-whisper + VAD) | ✅ | ✅ | 37.73 s | `--diarize` is a flag, not k=v |
| 4 | **whisper.cpp** (C++ / GGML, Metal) | ✅ | ✅ | 22.76 s | Confirmed Metal under UTM |
| 5 | **insanely-fast-whisper** (transformers) | ⚠️ Installed but doesn't run | ❌ | n/a | torchcodec/PyTorch ABI mismatch — see Finding F5 |

Comparison harness: `tools/whisper-compare.sh` runs all five against one input, captures wall time, dumps side-by-side outputs.

### Phase 2 — Gemma 4 install — DEFERRED

Pending Lieutenant decision on Gemma 4 E2B (smaller, 10 GB) vs E4B (larger, more capable). Required reading: `BRIEF.md` and the in-conversation research findings (Gemma 2/3 27B have no audio; only Gemma 4 E2B/E4B can do audio; mlx-vlm Issue #903 status check required before install).

### Phase 3 — Test cases (per BRIEF.md T1–T5)

- **T1 cold smoke** ✅ (per-backend, all 4 working backends pass on demo file)
- **T2 repeat invocation** — pending; harness already supports this
- **T3 resource bound** (memory under documented budget) — pending
- **T4 HTTPS-only egress** (vm-ops policy) — pending; spot-checked during installs (HF + GitHub HTTPS only)
- **T5 reboot survival** — pending

---

## Decisions (ADRs)

Empty placeholders to be filled as decisions firm up:

- **ADR-001a (Whisper variant)** — pending; need result of Phase 1 comparison on harder inputs
- **ADR-001b (Gemma variant)** — pending Phase 2 (E2B vs E4B vs the others)
- **ADR-002 (Whisper runtime per use case)** — pending after failure-input testing
- **ADR-003 (quantization)** — pending
- **ADR-004 (Metal under UTM)** — drafting

---

## Findings

### F1 — Metal IS exposed under UTM (2026-05-05)

The brief's open Q4 (Metal passthrough) is **resolved YES**.

Evidence:
- whisper.cpp `cmake -B build` reported `-- Metal framework found / -- Including METAL backend`.
- whisper.cpp at runtime: `ggml_metal_init: found device: Apple Paravirtual device / picking default device: Apple Paravirtual device / using MTL0 backend`.
- mlx-whisper ran without Metal-related errors and achieved 3.74 s warm-cache wall on a 14 s audio clip — performance consistent with Metal acceleration.

Performance under paravirtualised Metal on this VM:
- whisper.cpp (Metal, large-v3): 14 s audio → 22.76 s wall (~0.6× real-time, cold encode 6.3 s + decode 15.9 s).
- mlx-whisper (MLX/Metal, large-v3): 14 s audio → 3.74 s wall warm (3.7× real-time); 36.79 s first run (incl. 14 s of model download).

### F2 — All 5 candidate Whisper distros install on Python 3.13 via `uv tool`

`uv tool list` shows: openai-whisper v20250625, mlx-whisper v0.4.3, whisperx v3.8.5, insanely-fast-whisper v0.0.15. whisper.cpp builds from source via cmake into `tools/whisper.cpp/build/bin/`.

### F3 — `ffmpeg@7` is required for any tool that bundles `torchcodec`

`torchcodec` ships pre-compiled dylibs binding to `libavutil.56–59` (FFmpeg 4–7). The system default ffmpeg is now 8.x with `libavutil.60`. Workaround: `brew install ffmpeg@7` and either set `DYLD_FALLBACK_LIBRARY_PATH` (often stripped by SIP through wrapper binaries) or patch the dylib's rpath with `install_name_tool -add_rpath /opt/homebrew/opt/ffmpeg@7/lib …` followed by ad-hoc `codesign --force --sign - …`.

### F4 — Working backends produce textually-identical outputs but with subtle segmentation differences on the demo file

| Backend | Text |
|---|---|
| openai-whisper / mlx-whisper / whisperX | `…with MLXVLM. Just going to see…` |
| whisper.cpp | `…with MLXVLM, just going to see…` |

Same words; different sentence boundary inferred at the same audio position. This is exactly the kind of variation worth studying under harder (noisy / accented / overlapping-speech) inputs — see Phase 1 follow-up.

### F5 — `insanely-fast-whisper`: two compounding bugs (RESOLVED 2026-05-05 → see F27)

Bug 5a — torchcodec wants `libavutil.56–59`; system has `libavutil.60`. Workaround: ffmpeg@7 + rpath patch + ad-hoc resign.

Bug 5b — `libtorchcodec_core7.dylib` references the symbol `_torch_dtype_float4_e2m1fn_x2` from `libtorch_cpu.dylib`, not present in PyTorch 2.10. **Resolved by upgrading torch to 2.11.0** — see F27.

---

## Phase 1.5 — Synthetic Failure Corpus (2026-05-05)

9 synthesised inputs in `test-corpus/01-09.wav` covering documented Whisper failure categories. Run with `tests/run-failure-corpus.sh transcribe`. Results saved to `corpus-results/2026-05-05-114430-transcribe/SUMMARY.md`.

### F6 — VAD pre-filter is the silence/short-clip safety net

WhisperX's pyannote-VAD layer prevents the canonical `"Thank you"` / `"you"` hallucinations on silent audio (case 01: 30 s silence) and ≤1-second clips (case 04: 600 ms). Three of four backends hallucinate; whisperX produces empty output. Binary outcome on two independent inputs — pattern is structural, not noise.

### F7 — 6 kbps Opus codec round-trip breaks unfamiliar lexicon, differently per backend

Case 03 (Simon's clip → 6 kbps Opus → re-decoded). Same input, four backends, three distinct misperceptions of `MLXVLM`:

| Backend | What it heard |
|---|---|
| openai-whisper / whisperX / whisper.cpp | `NLXVLM` |
| mlx-whisper | `MLSVLM` (unique) |

Identical models would produce identical errors. They don't, so the backends are non-identical on degraded inputs. By contrast, **8 kHz sampling-rate downgrade (case 02) is NOT a failure mode** — all four produce clean output.

### F8 — Pink noise at high amplitude breaks ALL 4 backends; failure outputs diverge

Case 08 (pink noise mixed at amplitude 0.4 with speech at 1.0):
- openai-whisper: `"Thank you."`
- mlx-whisper: `"Thank you."`
- whisperX: `"Yes, ma'am."` (VAD didn't filter pink noise — speech-like spectrum)
- whisper.cpp: `"this"` (1 word salvaged)

Universal failure with three distinct hallucinations. **Pink noise is the canonical low-SNR failure for Whisper Large-v3.**

### F9 — Speaker overlap has two distinct failure shapes

Case 07 (Simon × Simon, 2 s offset):

| Family | Failure mode |
|---|---|
| PyTorch family (openai-whisper, mlx-whisper, whisperX) | Substitute unfamiliar acronym `MLXVLM → Gemma`; merge speakers into one transcript |
| whisper.cpp | **Sentence repetition** — replays first phrase. Segment splitter mishandles delay-overlap. |

No backend marked overlap. Whisper has no diarisation; choose accordingly.

### F10 — A 440 Hz tone overlay is not a failure mode

Case 06: pure-tone music distractor doesn't break parsing. Real music likely would; this is an underconstrained test. **Refined in F16 with a 3-tone chord; same outcome.**

### F11 — Pseudo-whispered synthesis is not a useful test

Case 09: highpass + compressor preserves pitch (real whispered speech is voiceless). All 4 parsed cleanly. **Refined in F15 with real ASMR-whispered speech — also not a failure mode for Large-v3.**

---

## Phase 1.6 — Real-World Failure Samples (2026-05-05)

5 additional inputs in `test-corpus/10-14.wav` from public sources. Three accent samples from [GMU Speech Accent Archive](https://accent.gmu.edu/) reading the standard "Please call Stella" passage; one real whispered ASMR clip from [archive.org](https://archive.org/details/ASMRWhisperingReading8r2ESNzVOOA); one richer chord-overlay synthesis. Results: `corpus-results/2026-05-05-141400-accents/SUMMARY.md`.

### F12 — Australian English `spoons → spurns` failure mode REPRODUCED in 3 of 4 backends

The Mozilla 2026 documented Australian-English failure case is real on this VM. Case 11 (Melbourne speaker, GMU SAA speakerid=140):

| Backend | Output of "Six **spoons** of fresh snow peas" |
|---|---|
| openai-whisper | "Six **spurns** of…" 🔴 |
| mlx-whisper | "Six **spurns** of…" 🔴 |
| **whisperX** | "Six **spoons** of…" ✅ |
| whisper.cpp | "Six **spurns** of…" 🔴 |

Australian /uː/ shifts toward /ɜː/ ("err"), and Whisper Large-v3's lexicon-prior maps it to `spurns`. **Only whisperX (faster-whisper / CTranslate2 backend) recovers the correct word** — likely a different beam-search / temperature default. This single finding strengthens whisperX's case as default backend significantly: it now wins on TWO independent failure modes (silence + Australian).

### F13 — Mumbai Indian English triggers normalization divergence between backends

Case 12 (GMU SAA speakerid=426, Mumbai Indian English):

| Backend | Output formatting |
|---|---|
| openai-whisper | unpunctuated, lowercased: "please call stella ask her to bring…" 🟡 |
| mlx-whisper | normal: "Please call Stella. Ask her to bring…" ✅ |
| whisperX | normal ✅ |
| whisper.cpp | unpunctuated, lowercased 🟡 |

Same model weights produce different normalisation behaviour by backend. Text content is correct in all 4 (`spoons`, not `spurns`). **Pipeline implication:** any downstream tool depending on consistent capitalisation/punctuation will see backend-dependent variation when accents trigger this codepath.

### F14 — Glasgow Scottish does NOT break Whisper

Case 10 (GMU SAA speakerid=82, Glasgow). All 4 backends transcribed cleanly. Despite Scottish English being notorious in older ASR literature, Whisper Large-v3's training appears to cover Glasgow rhotic consonants and vowel shifts well. Difference is only segmentation (comma vs period after "Stella" between mlx-whisper and the others).

### F15 — Real whispered ASMR speech does NOT break Whisper

Case 13 (30 s of YouTube ASMR speaker, extracted from archive.org). All 4 backends transcribed real whispered speech cleanly. Minor word-level errors (mlx-whisper: "I want it to" vs "I wanted to"; whisper.cpp: dropped 3 words in "there's a lot of things"). **No hallucinations, no major content loss.** Whisper's training set evidently covers whispered phonation well enough.

### F16 — A 3-note chord (C-E-G) doesn't break Whisper either

Case 14: richer than F10's 440 Hz tone. All 4 backends parsed cleanly, with the same minor punctuation drift seen in case 06. **Real music with vocals + dynamic-range / rhythm has not been tested directly.** Worth a follow-up if music+podcast scenarios become a concrete use case.

---

## Failure-mode count per backend (Phase 1.5 + 1.6 combined, 14 cases)

| Backend | 🔴 Hard fail | 🟠 Partial | 🟡 Drift | ✅ Clean |
|---|---:|---:|---:|---:|
| **whisperX** | **1** | 2 | 0 | **11** |
| mlx-whisper | 3 | 3 | 2 | 6 |
| whisper.cpp | 2 | 2 | 4 | 6 |
| openai-whisper | 4 | 3 | 3 | 4 |

WhisperX is dominant on this corpus.

---

## ADR-001a — Whisper backend defaults (DRAFT, evidence locked)

Based on F6, F8, F12, F13:

| Use case | Recommended | Reasoning |
|---|---|---|
| Default, unknown content | **whisperX** | VAD prevents silence-hallucinations; only backend to handle Australian English's `spoons` correctly; consistent normalisation |
| Speed-critical, known-clean speech | **mlx-whisper** | 3 s warm on a 14 s clip with paravirtualised Metal; same content quality as openai-whisper |
| Reproducibility / no Python | **whisper.cpp** | Single binary, GGML format; watch for sentence-repetition on overlap (F9) and lowercased output on Indian accents (F13) |
| Reference / debugging | openai-whisper | Slow CPU PyTorch; no special advantages on this corpus |

`insanely-fast-whisper` excluded — see F5.

---

## Phase 2 — Gemma 4 E4B install + corpus comparison (2026-05-05)

mlx-vlm 0.4.4 installed via `uv tool install mlx-vlm`. Issue #903 (audio gibberish in mlx-community quants) was closed via PR #931 and is fixed in 0.4.4 when using the **official** `google/gemma-4-*-it` models. No HuggingFace authentication required for download.

Smoke-test on Simon Willison's `demo-audio-for-gemma.wav`: model loaded, transcribed, peak memory 16.4 GB (fits in 64 GB), generation 27 tok/s. **Reproduced Simon's documented "right → front" error** — same audio, same model, same mistake on this VM.

Corpus run (14 inputs from Phase 1.5+1.6) completed in 2 min 30 s (warm cache, all 14 files). Outputs in `corpus-results/2026-05-05-150750-gemma4-E4B/SUMMARY.md`.

### F17 — Gemma 4 E4B works on this VM
mlx-vlm 0.4.4 + `google/gemma-4-E4B-it`, ~16 GB resident, ~27 tok/s. No auth required for the official model.

### F18 — Simon Willison's "right → front" failure reproduced
Same audio, same error documented in his April 12 2026 post. Persists across overlay variants (440 Hz, 3-tone chord, pseudo-whispered) — it's a learned acoustic confusion in the model, not a corruption artifact.

### F19 — Gemma 4 silently fails on silence/short/noise rather than hallucinating
Cases 01 (silence), 04 (600 ms), 08 (pink noise) → empty or near-empty output. **For pipelines that prefer "no output" over a wrong output, Gemma 4 is safer than 3 of 4 Whisper backends and equivalent to whisperX (VAD).**

### F20 — Australian English: a THIRD distinct misperception of "spoons"
- whisperX: "spoons" ✅
- openai-whisper / mlx-whisper / whisper.cpp: "**spurns**"
- Gemma 4 E4B: "**spuds**"
Three SOTA-tier models, three different errors on the same input.

### F21 — Gemma 4 hallucinates on real whispered speech
Case 13: "troubles I go through" → "**psychotherapy**" — a full lexical hallucination on real ASMR-quality whispered audio that Whisper Large-v3 handles cleanly (only minor word errors). Gemma 4's training distribution evidently doesn't cover whispered phonation.

### F22 — Gemma 4 routinely drops capitalisation and punctuation on accented English
Cases 05 (JFK), 10 (Glasgow), 11 (Melbourne), 12 (Mumbai) all lost capitalisation / periods. More pervasive than the whisper-side normalisation divergence (F13).

### Failure-mode count (4 Whisper backends + Gemma 4 E4B, 14 cases)

| Model | ✅ Clean | 🟡 Drift | 🟠 Partial | 🔴 Hard fail |
|---|---:|---:|---:|---:|
| **whisperX** | **11** | 0 | 2 | 1 |
| mlx-whisper | 6 | 2 | 3 | 3 |
| whisper.cpp | 6 | 4 | 2 | 2 |
| Gemma 4 E4B | 2 | 3 | 6 | 3 |
| openai-whisper | 4 | 3 | 3 | 4 |

Gemma 4 E4B sits between openai-whisper and whisper.cpp in raw-transcription quality; whisperX dominates the corpus.

---

## ADR-001b — Gemma variant (DRAFT, evidence locked)

| Use case | Recommended |
|---|---|
| **Audio → text only** | **Whisper (whisperX preferred)** — Gemma 4 E4B is dominated on every transcription metric in our corpus. |
| **Audio → reasoning over content** (summarise, classify, answer questions about what was said) | **Gemma 4 E4B** — Whisper can't do this. Alternative: two-stage Whisper → Gemma-4-text-only (no audio cost). |
| **Unknown-content where false-positives are worse than silence** | Either **Gemma 4 E4B** or **whisperX**. Both produce empty output rather than canonical hallucinations on silence/noise. |

Original brief framing ("can Gemma replace Whisper on this VM?") is answered **no** for raw transcription. Gemma 4's unique value is in combined-stack workflows that need reasoning over audio content.

E2B not tested — smaller (~3 GB Q4), would likely be worse than E4B, marginal value low given E4B is already dominated for the primary purpose.

---

## Phase 2.5 — Real music + speech ("podcast bed") (2026-05-05)

Two new test cases (15, 16) using public-domain instrumental music from Wikimedia Commons (Beethoven piano sonata + Negaraku orchestral anthem) overlaid with Simon's speech at typical podcast levels.

### F23 — Typical podcast bed does NOT break Whisper
Beethoven piano at −12 dB below voice (standard ducked-bed level used in podcast production) handled cleanly by **all 4 Whisper backends** (case 15). Generalises the earlier 440 Hz tone (case 06) and 3-tone chord (case 14) results: rich harmonic instrumental content, when ducked, is not a Whisper failure mode. Gemma 4 still made errors (`right→front`, `transcribed→squared`).

### F24 — Salience competition (music at near-equal level) IS the universal failure
Orchestral anthem at −4 dB below voice (case 16) broke **all 5 backends**:
- Whisper variants either **truncated** (lost everything after first sentence) or **hallucinated** (`It's good to see`).
- Gemma 4 produced near-complete hallucination (`This might be like once manner is taking a voice. This could see.`). Notably, Gemma 4 did NOT silently-fail here as it did on pink noise (F19) — orchestral content is heard as competing speech, not as ignorable ambient.

**Practical line:** music ducked ≥ 12 dB below voice = safe; music at near-equal level = ASR collapse. For media-production audio, pre-process with music attenuation or a vocal-isolation pass (Demucs / MDX-Net) before Whisper.

### Updated failure-mode count (16 cases, 5 backends)

| Backend | ✅ Clean | 🟡 Drift | 🟠 Partial | 🔴 Hard fail |
|---|---:|---:|---:|---:|
| **whisperX** | **12** | 0 | 2 | 2 |
| mlx-whisper | 7 | 2 | 3 | 4 |
| whisper.cpp | 6 | 4 | 2 | 4 |
| Gemma 4 E4B | 2 | 3 | 7 | 4 |
| openai-whisper | 5 | 3 | 3 | 5 |

WhisperX still dominant. ADR-001a unchanged.

---

## Phase 3 — Two-stage Whisper → Gemma 26B-A4B reasoning pipeline (2026-05-05)

Installed `unsloth/gemma-4-26b-a4b-it-UD-MLX-4bit` — Unsloth's mixed-precision MLX-4bit quantisation, designed around Gemma 4's PLE / ScaledLinear sensitivity (the issue that breaks standard MLX-4bit per F-side research). Pulls ~16 GB. Runs at 25.9 tok/s with **16.2 GB peak memory** — essentially the same memory footprint as Gemma 4 E4B because the MoE architecture activates only ~3.8 B params per token despite the 26 B total parameter count.

Two-stage pipeline (`tools/two-stage.sh`):
1. **Stage 1 — Transcription:** whisperX (large-v3, faster-whisper backend, no align/diarise) produces the text.
2. **Stage 2 — Reasoning:** Gemma 4 26B-A4B receives the transcript wrapped in a reasoning prompt and produces the answer.

### F25 — Two-stage pipeline works on this VM
mlx-vlm 0.4.4 + unsloth UD-MLX-4bit. Memory headroom comfortable (~16 GB peak each stage, but Whisper releases before Gemma loads — so peak is single-stage at any moment). Coherent, structured outputs that follow prompt templates (e.g. "summarise … then list one risk and one expected outcome" produced exactly that shape).

### F26 — Two-stage OUTPERFORMS Gemma 4 E4B alone on the audio→reasoning task
Direct comparison on the real-whispered ASMR clip (case 13):

| Approach | Output |
|---|---|
| Gemma 4 E4B alone (Phase 2, F21) | hallucinated `troubles I go through` → `**psychotherapy**` — full lexical hallucination |
| Two-stage Whisper→Gemma 26B-A4B | whisperX transcribed `troubles I go through` correctly; Gemma 26B-A4B then produced *"Resilient and cautiously optimistic (acknowledging difficulty while maintaining determination). Summary: The speaker is providing a brief update to reassure their audience that they will continue making videos despite ongoing health challenges."* |

The two-stage stack:
- Avoids Gemma 4 E4B's audio-side limitations (F18, F20, F21) by using Whisper for the audio.
- Brings Gemma's reasoning capability (which Whisper cannot do) on top of clean text.
- Costs ~16 GB peak memory at any one time (each stage runs sequentially, neither model is resident at the same time).
- Latency: ~30–60 s for a 14–30 s clip (Whisper transcription 3–25 s + Gemma reasoning 5–15 s for short outputs).

This **vindicates the audio→reasoning recommendation in ADR-001b** with empirical evidence on the Lieutenant's hardware.

### ADR-001b — UPDATED with empirical Phase 3 evidence

| Use case | Recommended | Notes |
|---|---|---|
| **Audio → text only** | **Whisper (whisperX preferred)** | Per ADR-001a |
| **Audio → reasoning over content** | **Two-stage: whisperX → Gemma 4 26B-A4B (UD-MLX-4bit)** | Empirically beats Gemma 4 E4B alone (F26). Total ~16 GB peak, ~30–60 s latency. |
| **Unknown content where false positives are worse than empties** | **whisperX** OR Gemma 4 E4B alone | Per F19; both produce empty rather than canonical hallucinations |

E2B remains untested (low marginal value).

---

## Phase 4 — `insanely-fast-whisper` revival (2026-05-05)

F5 known-fail resolved. Forced torch 2.11.0 into the tool venv via `uv tool install --python 3.13 --reinstall --with "torch>=2.11" insanely-fast-whisper`, re-applied the rpath patch (`install_name_tool -add_rpath /opt/homebrew/opt/ffmpeg@7/lib …`) and ad-hoc resign on `libtorchcodec_core7.dylib`. Verified the symbol `_torch_dtype_float4_e2m1fn_x2` now exports via `nm | grep`. Smoke test on Simon's clip succeeded.

### F27 — insanely-fast-whisper now FUNCTIONAL + ranked 2nd in the corpus

Run across all 16 corpus inputs (results in `corpus-results/2026-05-05-163500-ifw-revival/`):

| # | Test | IFW output | Verdict |
|---:|---|---|---|
| 01 | Silence (30 s) | `"Thank you."` | 🔴 hallucination |
| 02 | 8 kHz phone | clean | ✅ |
| 03 | 6 kbps Opus | "NLXVLM" | 🟠 |
| 04 | 600 ms | `"Thank you."` | 🔴 |
| 05 | JFK | clean | ✅ |
| 06 | 440 Hz tone | clean | ✅ |
| 07 | Speaker overlap | "MLXVLM → Gemma" substitution | 🟠 |
| 08 | Pink noise | `"yes"` | 🔴 (a *fourth* distinct hallucination on this input) |
| 09 | Pseudo-whispered | clean | ✅ |
| 10 | Glasgow Scottish | clean (proper punct) | ✅ |
| 11 | Melbourne Australian | "**spurns**" | 🔴 |
| 12 | Mumbai Indian | lowercase, no punct | 🟡 |
| 13 | Real whispered ASMR | clean | ✅ |
| 14 | 3-tone chord | clean | ✅ |
| 15 | Beethoven podcast bed | clean | ✅ |
| 16 | Orchestral near-equal | "this right here" | 🔴 |

IFW count: **8 ✅ / 1 🟡 / 3 🟠 / 4 🔴** — slots into 2nd place behind whisperX.

### Updated final leaderboard (16 cases, 6 backends)

| Backend | ✅ Clean | 🟡 Drift | 🟠 Partial | 🔴 Hard fail |
|---|---:|---:|---:|---:|
| **whisperX** | **12** | 0 | 2 | 2 |
| insanely-fast-whisper | 8 | 1 | 3 | 4 |
| mlx-whisper | 7 | 2 | 3 | 4 |
| whisper.cpp | 6 | 4 | 2 | 4 |
| openai-whisper | 5 | 3 | 3 | 5 |
| Gemma 4 E4B | 2 | 3 | 7 | 4 |

IFW behaves similarly to mlx-whisper (same model weights, similar CPU/MPS path) but with slightly cleaner outputs. Like the other PyTorch-family backends, it inherits the Australian "spurns" failure (F12) and lacks VAD-style silence safety. **Pink noise is a four-way distinct failure now**: openai-whisper "Thank you", mlx-whisper "Thank you", whisperX "Yes, ma'am", whisper.cpp "this", IFW "yes" — five backends, four different hallucinations.

### F28 — Pink noise produces FOUR distinct hallucinations across five backends

| Backend | Output on case 08 |
|---|---|
| openai-whisper | "Thank you." |
| mlx-whisper | "Thank you." |
| whisperX | "Yes, ma'am." |
| whisper.cpp | "this" |
| insanely-fast-whisper | "yes" |
| Gemma 4 E4B | ". king" |

Five Whisper-family backends (4 + IFW), four distinct hallucinations — and Gemma 4 E4B's near-empty `". king"` makes six total outputs. Pink noise is the canonical low-SNR failure but the *failure shape* is heterogeneous. **No two backends fail identically.**

### ADR-001a UPDATE — IFW slot

ADR-001a (Whisper backend defaults) gains one row:

| Use case | Recommended | Notes |
|---|---|---|
| Default, unknown content | **whisperX** | Unchanged |
| Speed-critical, known-clean | **mlx-whisper** | Unchanged |
| Reproducibility / no Python | **whisper.cpp** | Unchanged |
| **transformers-pipeline / batch / MPS-first workflows** | **insanely-fast-whisper** | NEW — comparable quality to mlx-whisper, integrates better with transformers pipelines downstream |
| Reference / debugging | openai-whisper | Unchanged |

### Install-recipe note

`uv tool install --reinstall` will **wipe the rpath patch** on `libtorchcodec_core7.dylib`. Re-apply after any reinstall:

```bash
torchcodec_dir=/Users/dev/.local/share/uv/tools/insanely-fast-whisper/lib/python3.13/site-packages/torchcodec
install_name_tool -add_rpath /opt/homebrew/opt/ffmpeg@7/lib "$torchcodec_dir/libtorchcodec_core7.dylib"
codesign --force --sign - "$torchcodec_dir/libtorchcodec_core7.dylib"
```

INSTALL.md updated to reflect this.

---

## Open questions (post Phase 4)

- Phase 3 hardening (T2 repeat, T3 resource bound, T4 network policy, T5 reboot survival) against all backends — formalise when?
- Music pre-processing (Demucs / MDX-Net source separation) before Whisper for media audio (F24) — scope as follow-on contract?
- 31B-dense Gemma 4 (text-only, no audio) for harder reasoning tasks — install for completeness?

---

## Test cases

| ID | Status | Notes |
|---|---|---|
| T1 cold smoke | ✅ 4/5 pass | demo-audio-for-gemma.wav; insanely-fast-whisper fails |
| T2 repeat | pending | re-run via `tools/whisper-compare.sh` |
| T3 resource bound | pending | RSS via `ps -axo rss,comm` during run |
| T4 HTTPS-only egress | pending (informally OK) | weights pulled from HF / GitHub over HTTPS |
| T5 reboot survival | pending | re-run harness after VM reboot |

---

## Session log

- **2026-05-05 11:03–11:30 (active session, 27 min so far)** — kickoff session opened from parking-lot deposit. Planning Q1 → gemma-on-vm chosen over Skills P1-CRITICAL. Q2 (variant) opened then preempted by audio file delivery → research established Whisper > Gemma for raw audio→translation → contract scope broadened. All 5 Whisper distributions installed; 4 working; Metal confirmed under UTM; comparison harness written and validated; PLAN/INSTALL/smoke files in this commit.
