# Audio Translation — Using the Best Free Software

A practical guide to transcribing and translating audio files locally on macOS Apple Silicon, **for $0 in API cost**. All evidence in this guide is from the empirical 16-case failure-corpus comparison documented in `PLAN.md` (findings F1–F28).

---

## TL;DR

| You want | Use |
|---|---|
| English transcript of English audio | `whisperx` |
| English transcript of non-English audio | `whisperx --task translate` |
| Non-English transcript or translation | Two-stage: `whisperx` → Gemma 4 26B-A4B |
| Just speed, audio is clean | `mlx_whisper` (3.7× real-time on Apple Silicon Metal) |
| Reproducibility, no Python | `whisper-cli` (whisper.cpp) |

**Cost:** $0. All open-weight models, all run locally, all pulled anonymously from HuggingFace.

**Hardware:** macOS arm64 (M-series chip), 16+ GiB RAM, ~25 GiB free disk.

---

## Why this stack — and what's "best"

We measured **6 backends across 16 audio failure cases** (silence, codec degradation, accents, music+speech, real ASMR-whispered speech, etc.). Final ranking by clean-output count:

| Backend | ✅ Clean / 16 | 🔴 Hard fails |
|---|---:|---:|
| **whisperX** | **12** | 2 |
| insanely-fast-whisper | 8 | 4 |
| mlx-whisper | 7 | 4 |
| whisper.cpp | 6 | 4 |
| openai-whisper | 5 | 5 |
| Gemma 4 E4B (audio-direct) | 2 | 4 |

**WhisperX wins decisively.** It uses Whisper Large-v3 weights, but adds a `pyannote` voice-activity-detection (VAD) pre-filter and the faster-whisper / CTranslate2 backend, both of which materially reduce failure rates compared to the alternatives running the *same model weights*.

**Why not Gemma 4 alone?** Gemma 4 E4B can transcribe audio directly (via mlx-vlm), but on our corpus it was the worst of the six. It hallucinated "psychotherapy" on real whispered speech (where Whisper got "troubles I go through") and reproduced Simon Willison's documented "right → front" error. Gemma 4 is **not the right tool for raw transcription**. Its unique value is *reasoning over* a clean transcript — which is exactly what the two-stage pipeline does.

---

## Quick start

### 1. Install (one time, ~25 GiB disk + ~5 min)

See `INSTALL.md` in this repo for the full reproducible recipe. The minimal install for translation use is:

```bash
brew install ffmpeg ffmpeg@7
uv tool install --python 3.13 whisperx
# Optional, for non-English-target translation:
uv tool install --python 3.13 mlx-vlm
```

First runs of each tool will pull the Whisper Large-v3 weights (~3 GiB) from HuggingFace anonymously. No login, no API key.

### 2. Transcribe English audio (most common case)

```bash
whisperx audio.wav \
  --model large-v3 \
  --task transcribe \
  --language en \
  --output_format txt \
  --no_align \
  --compute_type float32 \
  --output_dir output/
cat output/audio.txt
```

### 3. Translate non-English audio to English

Same command but with `--task translate` (Whisper's built-in always targets English):

```bash
whisperx audio.wav \
  --model large-v3 \
  --task translate \
  --output_format txt \
  --no_align \
  --compute_type float32 \
  --output_dir output/
```

### 4. Translate to a non-English target

Whisper itself only translates *into English*. For any other target, use the two-stage pipeline:

```bash
./tools/two-stage.sh audio.wav "Translate the transcript into Spanish."
./tools/two-stage.sh audio.wav "Translate to Mandarin Chinese, simplified script."
./tools/two-stage.sh audio.wav "Translate to French and add a one-line summary."
```

The script transcribes with whisperX (best raw quality) and then asks Gemma 4 26B-A4B to translate or otherwise reason over the transcript.

---

## Choose the backend deliberately

If whisperX doesn't fit your environment (e.g. you can't install Python tooling), pick a substitute from our measured leaderboard. The differences are real and documented:

### whisper.cpp (best when you need a single binary, no Python)

- C++ CLI, GGML model format, ~3 GiB on disk
- Runs Metal-accelerated under UTM/macOS (confirmed on `Apple Paravirtual device`)
- ~22 s wall on a 14 s clip with Metal
- Watch out: on speaker overlap, whisper.cpp **repeats** the first sentence verbatim instead of failing cleanly (PLAN F9)

```bash
ffmpeg -y -i audio.wav -ar 16000 -ac 1 -f wav input-16k.wav
whisper-cli -f input-16k.wav -m models/ggml-large-v3.bin --translate -of out -otxt
```

### mlx-whisper (fastest on Apple Silicon)

- Apple Metal-native via the MLX framework
- 14 s clip in ~3.7 s warm cache (~3.7× real-time)
- Slightly worse hard-failure count than whisperX (4 vs 2)

```bash
mlx_whisper audio.wav \
  --model mlx-community/whisper-large-v3-mlx \
  --task transcribe \
  --output-format txt --output-dir output/
```

### insanely-fast-whisper (transformers pipeline)

- Same `openai/whisper-large-v3` weights but invoked through a HuggingFace `transformers.pipeline`
- 8 / 16 clean — better than mlx-whisper despite same weights
- Has known install pitfalls; see `INSTALL.md` Section 6

```bash
insanely-fast-whisper \
  --file-name audio.wav \
  --model-name openai/whisper-large-v3 \
  --task transcribe --device-id mps \
  --transcript-path output.json
```

---

## Failure modes worth knowing about

These are documented in `PLAN.md` with full evidence. Heads-up so you don't get caught:

| Pattern | What happens | Mitigation |
|---|---|---|
| **Silent audio** | All backends except whisperX hallucinate "Thank you" / "you" / similar | Use whisperX (its VAD pre-filter mutes silence) |
| **Sub-1-second clips** | Same hallucination as silence | whisperX again; or trim and re-test |
| **6 kbps Opus codec** | Unfamiliar acronyms get garbled differently per backend (e.g. `MLXVLM` → `NLXVLM` / `MLSVLM`) | Don't rely on rare-word fidelity in heavily compressed audio |
| **Australian English /uː/** | `spoons` → `spurns` (in 4 backends) or `spuds` (in Gemma 4); whisperX gets it right | Use whisperX |
| **Pink noise + speech** | All 5 Whisper backends + Gemma 4 produce different hallucinations; SNR is below the model's training distribution | De-noise first (RNNoise, Demucs, or ffmpeg `afftdn`) |
| **Music near voice level** | All 6 backends collapse — truncate or hallucinate. Music ducked ≥ 12 dB below voice is fine | For media-production audio, run Demucs / MDX-Net source separation before Whisper |
| **Speaker overlap (crosstalk)** | No backend diarises; you get one merged transcript or sentence repetition (whisper.cpp specifically) | Use a separate diarisation tool (e.g. `pyannote.audio`) before transcription, or accept the merge |

---

## Two-stage pipeline (Whisper → Gemma reasoning)

For tasks that go *beyond* raw transcription/translation:

```bash
./tools/two-stage.sh audio.wav "Summarize the speaker's main topic in one sentence and identify their emotional state."
./tools/two-stage.sh audio.wav "Translate to French, then list the named entities mentioned."
./tools/two-stage.sh audio.wav "Was this person's tone positive, neutral, or negative? Quote the line that gave it away."
./tools/two-stage.sh audio.wav "Translate to Japanese (formal register), preserving any English technical terms."
```

The pipeline runs whisperX first (best transcription quality) and then sends the clean text to Gemma 4 26B-A4B (UD-MLX-4bit) with your reasoning prompt. Memory: 16 GB peak (sequential — never both models resident at once). Latency: 30–60 s for a 14–30 s clip.

This is **strictly better than Gemma 4's audio-direct mode** for our corpus (PLAN F26).

---

## Cost analysis — why this is free

| Component | Source | License | Cost |
|---|---|---|---|
| Whisper Large-v3 weights | OpenAI | MIT | $0 |
| whisperX | m-bain/whisperX | BSD-2 | $0 |
| faster-whisper backend | SYSTRAN | MIT | $0 |
| pyannote.audio (VAD) | pyannote | MIT | $0 |
| mlx-whisper | ml-explore/mlx | MIT | $0 |
| whisper.cpp | ggerganov | MIT | $0 |
| insanely-fast-whisper | sanchit-gandhi | Apache 2.0 | $0 |
| Gemma 4 26B-A4B (UD-MLX-4bit) | Google → Unsloth | Apache 2.0 | $0 |
| ffmpeg | FFmpeg | LGPL/GPL | $0 |
| Hardware | Your existing macOS arm64 | n/a | $0 |

**All free, all local, all reproducible.** No HuggingFace authentication required for any of the model pulls (anonymous downloads work; HF only logs you for rate-limit purposes — not gating).

The only thing the Lieutenant needs is:
- a Mac with Apple Silicon
- ~25 GiB of disk
- one-time install (~5 min wall)

---

## See also

- [`INSTALL.md`](../INSTALL.md) — reproducible setup recipe
- [`PLAN.md`](../PLAN.md) — full F1–F28 findings + ADR-001a/b
- [`tools/whisper-compare.sh`](../tools/whisper-compare.sh) — side-by-side backend comparison harness
- [`tools/two-stage.sh`](../tools/two-stage.sh) — Whisper → Gemma reasoning pipeline
- [`tests/run-failure-corpus.sh`](../tests/run-failure-corpus.sh) — batch runner over the 16-case test corpus
