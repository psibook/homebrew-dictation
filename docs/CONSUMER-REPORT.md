# Audio Translation — Consumer Reports

A side-by-side comparison of the 6 backends measured in this contract, grounded in 16 audio failure cases (PLAN.md F1–F28). Designed to answer "**which one should I use for X?**" at a glance.

**Harvey balls:** ● excellent · ◕ very good · ◐ good · ◔ fair · ○ poor / unable

---

## Master score card

| Criterion | whisperX | insanely-fast-whisper | mlx-whisper | whisper.cpp | openai-whisper | Gemma 4 E4B |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Raw transcription accuracy** (16-case corpus, clean count) | ● 12 | ◕ 8 | ◐ 7 | ◐ 6 | ◔ 5 | ○ 2 |
| **Hard-failure rate** (lower is better) | ● 2 | ◐ 4 | ◐ 4 | ◐ 4 | ○ 5 | ◐ 4 |
| **Silence / short-clip safety** (VAD or graceful) | ● VAD pre-filter | ○ "Thank you" hallucination | ○ "Thank you" | ○ "Thank you" | ○ "Thank you" | ◕ silently empty |
| **Speed on 14 s clip (warm cache)** | ◐ ~38 s | ◕ ~22 s | ● **3.74 s** | ◐ ~23 s | ○ ~43 s | ◕ ~14 s |
| **Memory peak** | ● ~3 GB | ◕ ~5 GB (MPS) | ● ~3 GB | ● ~3 GB | ● ~3 GB | ◐ 16 GB |
| **Apple Silicon native (Metal)** | ◕ via faster-whisper | ◕ via MPS | ● MLX-native | ● Metal | ○ CPU-only PyTorch | ● MLX-native |
| **Install simplicity** | ● `uv tool install whisperx` | ◔ uv install + torch≥2.11 + rpath patch | ● `uv tool install mlx-whisper` | ◐ git clone + cmake build | ● `uv tool install openai-whisper` | ◐ uv install mlx-vlm + accept license |
| **Single binary, no Python** | ○ Python | ○ Python | ○ Python | ● `whisper-cli` only | ○ Python | ○ Python |
| **Translation to non-English target** (out-of-the-box) | ○ → English only | ○ → English only | ○ → English only | ○ → English only | ○ → English only | ◐ multilingual via prompt |
| **Reasoning over content** (summarise, classify, etc.) | ○ transcription only | ○ transcription only | ○ transcription only | ○ transcription only | ○ transcription only | ● native LLM |
| **Diarisation (who spoke when)** | ◕ via `--diarize` (pyannote) | ◔ via `--hf-token` (pyannote) | ○ none | ○ none | ○ none | ○ none |
| **Word-level timestamps** | ● via `--no_align` off | ◕ `--timestamp word` | ◐ supported | ◕ `-ml 1` | ◐ supported | ○ chunks only |
| **License** | ● BSD-2 | ● Apache 2.0 | ● MIT | ● MIT | ● MIT | ● Apache 2.0 (Gemma terms) |
| **HuggingFace auth required?** | ◕ only for diarisation | ◕ only for diarisation | ● anonymous | ● anonymous | ● anonymous | ● anonymous |
| **Cost per call** | ● $0 | ● $0 | ● $0 | ● $0 | ● $0 | ● $0 |

---

## "Best for…" lookup

| If your priority is… | Use | Why (with evidence pointer) |
|---|---|---|
| **Best raw transcription accuracy on unknown audio** | **whisperX** | 12/16 clean — the only backend that handles silence (F6), short clips (F6), and Australian English correctly (F12) |
| **Speed-critical, audio is known-clean** | **mlx-whisper** | 3.74 s on a 14 s clip warm cache (3.7× real-time) — Metal-native; same content quality as openai-whisper for clean speech |
| **Single binary, no Python toolchain** | **whisper.cpp** | One C++ binary; reproducible build via cmake; Metal-accelerated under UTM (F1) |
| **Translate non-English audio to English** | **whisperX** with `--task translate` | Whisper's built-in always targets English; whisperX inherits this and stays accurate |
| **Translate to a non-English target** (Spanish, Mandarin, French, Japanese, …) | **Two-stage: whisperX → Gemma 4 26B-A4B** (`tools/two-stage.sh`) | Whisper alone can't target non-English; Gemma 4 alone is bad at audio (F18, F21). The two-stage pipeline beats both alone on the same audio (F26) |
| **Summarise, classify, or answer questions about audio content** | **Two-stage** | Whisper gives you the transcript; Gemma 4 26B-A4B reasons over it (F25, F26) |
| **Diarisation (multiple speakers)** | **whisperX** with `--diarize` flag | Uses pyannote.audio; needs an HF token. No other backend in this set diarises out of the box |
| **Word-level timestamps for captioning / karaoke** | **whisperX** (drop `--no_align`) or **whisper.cpp** with `-ml 1` | Both produce word-time alignments |
| **Lowest install friction** | **mlx-whisper** | One `uv tool install`; anonymous HF download; no rpath patches, no compile step |
| **Reproducibility (same output on a fresh VM)** | **whisper.cpp** | Single binary + GGML model file + ffmpeg input. No Python env to drift over time |
| **Transformers-pipeline integration downstream** | **insanely-fast-whisper** | Thin (`pipeline("automatic-speech-recognition", …)`); fits naturally into HuggingFace pipelines + accelerators |

---

## "Avoid for…" — known sharp edges

| Don't use this tool when… | Why |
|---|---|
| **Audio is silent or sub-1-second** → don't use openai-whisper, mlx-whisper, whisper.cpp, or insanely-fast-whisper | All four hallucinate `"Thank you."` / `"you"` / `"Yes, ma'am."` / `"yes"` — F6, F28 |
| **Heavily codec-degraded** → don't trust rare-word fidelity in any backend | Each backend mis-perceives unfamiliar lexicon differently — F7 |
| **Australian English** → don't use openai-whisper, mlx-whisper, whisper.cpp, insanely-fast-whisper, or Gemma 4 | Five of the six get `"spoons"` wrong as `"spurns"` or `"spuds"` — F12, F20. Only whisperX is correct |
| **Pink/white noise SNR-dominant** → all 6 backends fail | Different hallucinations from each, no clean recovery — F8, F28 |
| **Music at near-equal level with speech** → all 6 backends collapse | Pre-process with Demucs / MDX-Net source separation — F24 |
| **Multi-speaker with crosstalk** → no single-pass backend handles this | whisper.cpp specifically repeats sentences; PyTorch family merges speakers and substitutes rare words — F9. Use diarisation first |
| **Real-time streaming** → none of these | All run batch / chunked. Out-of-scope (`whisper-streaming`, `Distil-Whisper` are the streaming options) |
| **Audio→text where quality matters** → don't use Gemma 4 E4B alone | 2/16 clean. Reproduces Simon Willison's "right→front" error (F18); hallucinated "psychotherapy" on real whispered speech (F21) |
| **Reasoning about audio content** → don't use any Whisper backend alone | Whisper is transcription-only. Use the two-stage pipeline |

---

## Five-second decision tree

```
Audio file in hand
        │
        ▼
Need TEXT or REASONING about content?
        │
        ├── Just text ──▶ Target language English?
        │                    │
        │                    ├── YES ──▶ whisperX --task transcribe (or --task translate
        │                    │           if source is non-English)
        │                    │
        │                    └── NO  ──▶ Two-stage: whisperX → Gemma 4 26B-A4B
        │                                with prompt "Translate to <target>"
        │
        └── Reasoning ──▶ Two-stage: whisperX → Gemma 4 26B-A4B
                          with prompt "<your task>"
```

If whisperX is unavailable for any reason:
- Need Apple-Silicon speed → `mlx-whisper`
- Need single-binary reproducibility → `whisper.cpp`
- Need transformers-pipeline integration → `insanely-fast-whisper`
- Reference / debugging → `openai-whisper`

---

## "When can I use it for free?" — reality check

Every tool in this report is **free** in every meaningful sense:

| Cost dimension | Reality |
|---|---|
| **Software license** | All MIT / BSD / Apache 2.0 (Gemma uses the Gemma terms — also permissive for personal/commercial use) |
| **API call cost** | $0 — runs entirely on your hardware |
| **Cloud / network cost** | Only the one-time model-weight download (~3 GB Whisper, ~16 GB Gemma 4 26B-A4B); thereafter offline-capable |
| **Storage** | ~25 GB for the full stack (Whisper + Gemma 4 26B-A4B); ~3 GB if you only install one Whisper backend |
| **Hardware** | Existing Apple Silicon Mac with ≥ 16 GB RAM; nothing to buy |
| **Account / auth** | Anonymous HuggingFace download for everything except `--diarize` (which needs a free HF token for pyannote) |

The single setup-time cost: **~5 minutes wall** to install (most of it is the `large-v3` weights downloading from HuggingFace at ~50 MB/s).

---

## See also

- [`USING-TRANSLATION.md`](USING-TRANSLATION.md) — task-oriented how-to guide with copy-paste commands
- [`../INSTALL.md`](../INSTALL.md) — reproducible setup recipe
- [`../PLAN.md`](../PLAN.md) — full F1–F28 findings + ADR-001a/b
- [`../skill/audio-translate/SKILL.md`](../skill/audio-translate/SKILL.md) — Claude-skill artifact
- [`../tools/two-stage.sh`](../tools/two-stage.sh) — Whisper → Gemma reasoning pipeline
- [`../corpus-results/`](../corpus-results/) — per-file outputs from each backend across all 16 cases
