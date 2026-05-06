---
name: audio-translate
description: Use this skill when the user wants to transcribe or translate an audio file locally for free on macOS Apple Silicon. Triggers on filenames ending in .wav/.mp3/.m4a/.flac/.ogg/.opus/.webm or phrases like "transcribe this", "translate this audio", "what does this voice memo say", "convert audio to text", "what language is this", "translate to Spanish/French/etc". Skill output is the transcript or translation, always for $0 API cost using local open-weight models.
---

# audio-translate — local, free transcription and translation

This skill teaches you to handle any "audio → text" or "audio → translation" task on macOS Apple Silicon using locally-run open-weight models. Total cost: **$0**. No API keys. No HuggingFace authentication. No cloud dependencies.

The full evidence base for the recommendations below is in [`gemma-on-vm/PLAN.md`](../../continental/software/cases/gemma-on-vm/PLAN.md) findings F1–F28 — empirical comparison of 6 backends across 16 audio failure cases.

## Decision tree

1. **What does the user want?**
   - Transcript in **English**, source is already English → use **whisperX `--task transcribe`**.
   - Transcript in **English**, source is some other language → use **whisperX `--task translate`** (Whisper's built-in always targets English).
   - Translation to **a non-English target** (Spanish, Mandarin, etc.) → use the **two-stage pipeline** (whisperX → Gemma 4 26B-A4B).
   - **Reasoning over the audio** (summary, emotion, named entities, classification) → two-stage pipeline.

2. **Is whisperX installed?** Check with `which whisperx`. If not, walk the user through the install (one command via `uv`). See "Install" section below.

3. **Is the audio file at a path you can reach?** On UTM VMs the courier directories are `/Volumes/My Shared Files/send-to-vm/` (incoming) and `/Volumes/My Shared Files/receive-from-vm/` (outgoing). Files in those directories are visible from inside the VM.

## The commands

### Transcribe English audio

```bash
whisperx <FILE.wav> \
  --model large-v3 \
  --task transcribe \
  --language en \
  --output_format txt \
  --no_align \
  --compute_type float32 \
  --output_dir <OUTDIR>
```

`--no_align` skips word-level timestamp alignment (you don't need it for plain transcripts and it requires extra model downloads). `--compute_type float32` is needed when MPS `float16` paths fail, which they sometimes do under UTM.

### Translate any-language audio to English

Same command, change `--task transcribe` to `--task translate`. Drop `--language en`.

### Translate to a non-English target

Use the two-stage pipeline at `tools/two-stage.sh` in the `gemma-on-vm` repo:

```bash
./tools/two-stage.sh <FILE.wav> "Translate the transcript into <TARGET LANGUAGE>."
```

This is whisperX's transcript piped into Gemma 4 26B-A4B (UD-MLX-4bit, MoE, ~16 GB peak memory). Works for any prompt:

```bash
./tools/two-stage.sh audio.wav "Translate to Mandarin Chinese, simplified script."
./tools/two-stage.sh audio.wav "Summarize in one sentence and identify the speaker's emotional state."
./tools/two-stage.sh audio.wav "Translate to Japanese in formal register, preserving English technical terms."
```

If `tools/two-stage.sh` is not present, the equivalent two commands are:

```bash
TRANSCRIPT=$(whisperx <FILE.wav> --model large-v3 --task transcribe --language en \
  --output_format txt --no_align --compute_type float32 --output_dir /tmp/twostage)
mlx_vlm.generate \
  --model unsloth/gemma-4-26b-a4b-it-UD-MLX-4bit \
  --prompt "Translate the following transcript into <TARGET LANGUAGE>: $(cat /tmp/twostage/*.txt)" \
  --max-tokens 1000 --temperature 0.7
```

## Install (one-time, ~5 min, ~25 GiB disk)

```bash
brew install ffmpeg ffmpeg@7   # ffmpeg@7 is needed by torchcodec for the IFW backend
uv tool install --python 3.13 whisperx
uv tool install --python 3.13 mlx-vlm   # only if user needs translation to non-English
```

First runs pull the Whisper large-v3 weights (~3 GiB) and Gemma 4 26B-A4B weights (~16 GiB) anonymously from HuggingFace. No HF authentication required.

## Why these tools (and not others)

I measured 6 backends across 16 failure cases and recorded the results in `gemma-on-vm/PLAN.md`. Headlines:

- **whisperX won** — 12 of 16 cases clean, 2 hard failures. Uses VAD to filter silence (preventing the canonical `Thank you` hallucination on silent or sub-1-second inputs) and the faster-whisper / CTranslate2 backend (which gets the documented Mozilla 2026 Australian-English `spoons` case right where every other backend hears `spurns`).
- **Gemma 4 E4B alone is bad at audio** — 2 of 16 clean. Reproduces Simon Willison's documented `right → front` error and hallucinated `psychotherapy` on real whispered speech where Whisper got the correct words. **Use Gemma only as a reasoner over Whisper's transcript, never as the audio model directly.**
- **Pink noise breaks everything.** All 6 backends produce different hallucinations on the same input. If the audio is genuinely noise-dominant, no current open-weight tool will recover the speech.
- **Music ducked ≥ 12 dB below voice is fine.** Music at near-equal level breaks all 6 backends. For podcast/media content with prominent music, pre-process with Demucs or MDX-Net source separation before Whisper.

## Common failure modes to warn the user about

| Symptom | What's happening | Workaround |
|---|---|---|
| Audio is silent or very short → output is `Thank you.` | Hallucination from Whisper's training-data subtitle credits | Use whisperX (its VAD masks silence) |
| Australian English speaker says `spoons` → output is `spurns` | Vowel-shift confusion in the lexicon prior | whisperX recovers the correct word; other backends do not |
| Phone-quality / heavy codec audio garbles unfamiliar names | Phoneme degradation below model's training distribution | Use the cleanest source you can; warn user |
| Music near voice level → output is truncated or hallucinated | All current open-weight ASR tools collapse here | Pre-process with Demucs (source separation) or RNNoise (denoising) |
| Multiple overlapping speakers → one merged transcript | Whisper has no diarisation | Run pyannote.audio for diarisation first if speaker turns matter |

## Cost summary

| Component | License | Cost |
|---|---|---|
| Whisper Large-v3 (OpenAI) | MIT | $0 |
| whisperX (m-bain) | BSD-2 | $0 |
| Gemma 4 26B-A4B (Google → Unsloth UD-MLX-4bit quant) | Apache 2.0 | $0 |
| mlx-vlm runtime | MIT | $0 |
| ffmpeg (LGPL build) | LGPL | $0 |
| HuggingFace anonymous downloads | n/a | $0 |
| Hardware (existing macOS arm64) | n/a | $0 |
| **TOTAL** | | **$0** |

No API keys, no quotas, no metering, no cloud round-trip.

## When NOT to use this skill

- The user wants real-time streaming transcription (Whisper Large-v3 is not streaming-friendly; consider `whisper-streaming` or `Distil-Whisper` instead — out of scope here).
- The user is on Linux/Windows (the Apple-Silicon-specific recommendations don't apply; the recipe should pivot to CUDA / CPU paths).
- The user needs guaranteed accuracy on rare proper nouns / technical jargon (no current open-weight ASR is reliable here; warn explicitly).
- The user wants to **diarise** (separate speakers). Whisper itself doesn't diarise. whisperX has a `--diarize` flag that uses pyannote.audio and works, but is out of scope of this skill.

## Reference layout (for reproducibility)

This skill is the user-facing distillation of empirical work in:

- `~/continental/software/cases/gemma-on-vm/` — the contract repo with installs, harnesses, 16-case corpus, and per-backend outputs
- `gemma-on-vm/PLAN.md` — F1–F28 findings + ADR-001a (Whisper backend defaults) + ADR-001b (Gemma variant for audio→reasoning)
- `gemma-on-vm/INSTALL.md` — reproducible setup recipe
- `gemma-on-vm/docs/USING-TRANSLATION.md` — extended user-facing how-to
- `gemma-on-vm/tools/two-stage.sh` — the Whisper → Gemma 4 26B-A4B reasoning pipeline
