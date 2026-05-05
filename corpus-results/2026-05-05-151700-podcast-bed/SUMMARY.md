# Real Music + Speech ("Podcast Bed") — Phase 2.5

**Date:** 2026-05-05 15:17
**Prompt to Gemma 4:** `"Transcribe this audio."`
**Whisper task:** `transcribe`, language `en`

## Test cases

| # | Test | Source | Mix |
|---|---|---|---|
| 15 | Beethoven Piano Sonata 1 (PD, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Beethoven_piano_sonata_1.ogg)) + Simon's clip | Piano instrumental, classical, single line | Music **ducked** at 25 % volume, weights `1 0.4` (music ~ −12 dB below voice) — typical podcast bed |
| 16 | Negaraku instrumental anthem (PD, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Negaraku_instrumental.ogg)) + Simon's clip | Full orchestral, dense | Music at 50 % volume, weights `1 0.6` (music ~ −4 dB below voice) — harder, near-equal levels |

## Outputs

### 15 — Beethoven piano (ducked bed, typical podcast scenario)

| Backend | Output |
|---|---|
| openai-whisper | "This right here is a quick voice memo, I want to try it out with MLXVLM, just going to see if it can be transcribed by Gemma and how well that works." | ✅ |
| mlx-whisper | "This right here is a quick voice memo I want to try it out with MLXVLM Just going to see if it can be transcribed by Gemma and how well that works" | ✅ |
| whisperX | "This right here is a quick voice memo I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works." | ✅ |
| whisper.cpp | "This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works." | ✅ |
| **Gemma 4 E4B** | "This **front** here is a quick voice memo. I want to try it out with mlx vlm just going to see if it can be **squared** by gemma and how that works." | 🟠 |

**ALL 4 Whisper backends transcribe a typical podcast bed cleanly.** Gemma 4 makes the persistent right→front error AND additionally hallucinates "transcribed → squared".

### 16 — Orchestral anthem, near-equal levels (the harder test)

| Backend | Output |
|---|---|
| openai-whisper | "This right here is a quick voice memo." | 🔴 truncated (lost ~7 s) |
| mlx-whisper | "This right here is a quick voice memo." | 🔴 same truncation |
| whisperX | "This right here is a quick voice memo. **It's good to see.**" | 🔴 truncated + hallucinated |
| whisper.cpp | "this right here" | 🔴 almost everything lost |
| **Gemma 4 E4B** | "This might be like **once manner is taking a voice**. This could see." | 🔴 near-complete hallucination |

**🔴 ALL 5 backends fail.** This is the universal-failure case for music+speech at near-equal volumes.

## New findings (PLAN.md F23–F24)

### F23 — Typical podcast bed does NOT break Whisper

Beethoven piano at −12 dB below voice (the standard ducked-bed level used in podcast production) is handled cleanly by **all four Whisper backends**. The 440 Hz pure-tone (case 06) and 3-tone chord (case 14) earlier results extrapolate correctly: rich harmonic instrumental content, when ducked properly, is not a Whisper failure mode.

### F24 — Salience competition (music near voice level) IS the universal failure

Orchestral music at −4 dB below voice (busier bed, near-equal volumes) breaks **all five backends**:

- Whisper variants either **truncate** (lose everything after first sentence) or **hallucinate** ("It's good to see").
- Gemma 4 E4B **does not silently fail** here (unlike F19's pink-noise outcome) — instead it produces **near-complete hallucination**. The salience-competition signal differs from white/pink noise: the encoder treats orchestral content as competing speech rather than as ambient noise to ignore.

**Practical line:** Music **ducked** = safe; music at **near-equal level** = ASR collapse. For pipelines processing media-production audio (broadcast, film mix), pre-process to attenuate music ≥ 12 dB below voice or use a music-source-separation step (e.g. Demucs, MDX-Net) before Whisper.

## Updated failure-mode count (16 cases, 5 backends)

| Backend | ✅ Clean | 🟡 Drift | 🟠 Partial | 🔴 Hard fail |
|---|---:|---:|---:|---:|
| **whisperX** | **12** | 0 | 2 | 2 |
| mlx-whisper | 7 | 2 | 3 | 4 |
| whisper.cpp | 6 | 4 | 2 | 4 |
| Gemma 4 E4B | 2 | 3 | 7 | 4 |
| openai-whisper | 5 | 3 | 3 | 5 |

Test 15 added 1 ✅ to whisperX, mlx-whisper, openai-whisper, whisper-cpp; 1 🟠 to Gemma 4. Test 16 added 1 🔴 to all 5.

WhisperX still dominant (12 of 16 clean). Gemma 4 still last on raw transcription quality but unique-value-justified for reasoning-over-content workflows.

## Implications

- **ADR-001a unchanged:** whisperX is still the audio-→-text default for unknown content.
- **New operational note:** for media-production audio, pre-process with music attenuation (or a vocal-isolation pass) BEFORE the Whisper step.
- **Gemma 4 audio robustness ranking refined:** silently-fails on white/pink noise (F19); hallucinates on salience-competing music (F24). Different acoustic distractors, different failure shapes.
