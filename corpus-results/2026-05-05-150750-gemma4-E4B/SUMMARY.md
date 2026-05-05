# Gemma 4 E4B vs Whisper — Failure Corpus Comparison

**Date:** 2026-05-05 15:07
**Model:** `google/gemma-4-E4B-it` via `mlx_vlm.generate` 0.4.4
**Prompt:** `"Transcribe this audio."`
**Hardware:** Continental VM (Apple M3 Max paravirtualised under UTM, Metal exposed as Apple Paravirtual device)
**Memory peak:** 16.4 GB (fits in 64 GB)
**Throughput:** ~27 tok/s generation, ~75 tok/s prompt

## Headline

**Gemma 4 E4B silently FAILS rather than hallucinates** on silence / short clips / pink noise — but makes more content errors than Whisper Large-v3 on clear speech, with **distinctive failure modes Whisper does not exhibit**:
- "right" → "**front**" (Simon Willison's documented April 12 2026 failure case, reproduced here)
- "spoons" → "**spuds**" on Australian English (a THIRD distinct misperception, after Whisper's "spoons" and "spurns")
- "troubles I go through" → "**psychotherapy**" on real whispered speech (full hallucination)

## Per-case results

Legend (against Whisper baseline):
✅ correct or better than Whisper
🟡 drift (capitalisation/punctuation)
🟠 word-level errors but mostly comprehensible
🔴 hard failure or significant hallucination

| # | Test | Gemma 4 E4B output | vs Whisper |
|---:|---|---|---|
| 01 | Silence (30 s) | (empty) | ✅ Better than 3/4 Whisper backends — no hallucination, equivalent to whisperX |
| 02 | 8 kHz phone-quality | "voicememo I want to try out with **XLM VLM**" | 🟠 Word errors; Whisper clean |
| 03 | 6 kbps Opus | "I want to try that with **NLMNquicksec**" | 🔴 Garbled; Whisper had only N/M errors |
| 04 | 600 ms clip | (empty) | ✅ Better than 3/4 Whisper — no hallucination |
| 05 | JFK canonical | "and so my fellow americans ask not what your country…" | 🟡 Lowercased + no punctuation; content correct |
| 06 | 440 Hz tone | "This **front** here is a quick voice memo… try that with **XLVM**" | 🟠 Two word errors; Whisper clean |
| 07 | Speaker overlap (Simon × Simon) | "This front here is a quick voice memo **this front here is** i want to try that with **Amlex** i want to try that out with **Amlex**" | 🟠 Same repetition mode as whisper.cpp, plus substitution |
| 08 | Pink noise + speech | ". king" | 🟠 Gave up rather than hallucinate "Thank you" / "Yes, ma'am" — defensible failure |
| 09 | Pseudo-whispered (synth) | "This **front** here…" | 🟡 The right→front bug persists |
| 10 | Glasgow Scottish | "please call stella ask her to bring…" | 🟡 Lowercased, no punctuation; content correct |
| 11 | **Melbourne Australian** | "six **spuds** of fresh snow peas" | 🔴 NEW misperception: "spuds" (Whisper variants got "spoons" or "spurns") |
| 12 | Mumbai Indian | "and a **new** snack for her brother Bob" | 🟠 "maybe" → "new" (Whisper got "maybe") |
| 13 | **Real whispered ASMR** | "pull through whatever uh trouble **psychotherapy** with my health" | 🔴 HALLUCINATION: "troubles I go through" → "psychotherapy" |
| 14 | 3-tone chord overlay | "This **one** here is a quick voice memo" | 🟠 right → "one" this time (different from "front") |

## Failure-mode count

| Backend | ✅ Clean | 🟡 Drift | 🟠 Partial | 🔴 Hard fail |
|---|---:|---:|---:|---:|
| **whisperX** (Whisper baseline winner) | 11 | 0 | 2 | 1 |
| Gemma 4 E4B | 2 | 3 | 6 | 3 |
| mlx-whisper | 6 | 2 | 3 | 3 |
| whisper.cpp | 6 | 4 | 2 | 2 |
| openai-whisper | 4 | 3 | 3 | 4 |

## Significant findings

### F17 — Gemma 4 E4B works on this VM
mlx-vlm 0.4.4 + official `google/gemma-4-E4B-it`. No HF auth required for download. Memory: 16.4 GB peak, 27 tok/s generation, 75 tok/s prompt. Issue #903 (audio gibberish) is fixed (PR #931).

### F18 — Simon Willison's "right → front" error reproduced
Same clip, same model, same error. Validates the documented April 12 2026 limitation. Persists across overlay variants (440 Hz tone, 3-tone chord, pseudo-whispered) — it's a learned acoustic confusion, not a corruption-specific artifact.

### F19 — Gemma 4 silently fails on silence/short clips/noise
Cases 01 (silence), 04 (600 ms), 08 (pink noise) all produced empty or near-empty output rather than the "Thank you" hallucination Whisper exhibits. **For pipelines that prefer "no output" over "wrong output" on uncertain audio, Gemma 4 is the safer choice** — though whisperX (with VAD) achieves the same outcome on silence/short clips with cleaner content elsewhere.

### F20 — Australian English: a THIRD distinct misperception
Whisper variants split between "spoons" (whisperX, correct) and "spurns" (others). **Gemma 4 produced "spuds"** — a unique mishearing not seen in any Whisper backend. The acoustic cluster of /uː/ → /ʌ/ + /d/ reflects a different lexicon prior. Useful as a calibration data point: same input, three SOTA-tier models, three different errors.

### F21 — Hallucination on real whispered speech
Case 13: Gemma 4 produced "**psychotherapy**" where the speaker said "troubles I go through". This is a full lexical hallucination on real ASMR-quality whispered audio — content Whisper Large-v3 handled cleanly (only minor word errors). Gemma 4's voice-memo training distribution evidently doesn't cover whispered phonation well.

### F22 — Loss of capitalisation/punctuation on accented English
Cases 10 (Glasgow), 11 (Melbourne), 12 (Mumbai) all produced lowercased / no-period output from Gemma 4. The standard JFK clip (case 05) and Simon's clip (case 02) also lost capitalisation. **This is a more pervasive issue than Whisper's case-13 / case-12 normalisation divergence.**

## ADR-001b draft (Gemma variant)

| Use case | Recommended | Reasoning |
|---|---|---|
| **Audio → text only** | **Whisper (whisperX preferred)** | Gemma 4 E4B is dominated on every speech-recognition metric in this corpus. |
| **Audio → reasoning over content** (summarise, classify, answer questions about what was said) | **Gemma 4 E4B** | The unique value of Gemma 4 — Whisper can't do this. Two-stage Whisper→Gemma-4-text-only is the alternative (no audio cost). |
| **Audio of unknown content where false positives are worse than empties** | **Gemma 4 E4B** OR **whisperX** | Both silently produce empty output rather than hallucinations on silence/noise. Pick whichever fits the rest of the pipeline. |

The contract's original framing ("can Gemma replace Whisper on this VM?") is answered: **no, not for raw transcription**. But Gemma 4 has clear unique value for combined-stack workflows where reasoning over audio content is needed.

`google/gemma-4-E2B-it` was not tested. It's smaller (~3 GB Q4) and would presumably be worse than E4B; the marginal value of testing it is low given E4B is already dominated by whisperX for this contract's primary purpose.
