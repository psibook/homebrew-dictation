# Phase 3 — Two-Stage Whisper → Gemma 26B-A4B Pipeline

**Date:** 2026-05-05 16:24
**Stage 1:** whisperX large-v3 (CTranslate2 / faster-whisper backend), `--no_align`, `--compute_type float32`
**Stage 2:** unsloth/gemma-4-26b-a4b-it-UD-MLX-4bit (MoE, ~16 GB peak, 25.9 tok/s)
**Pipeline:** `tools/two-stage.sh <audio> "<reasoning prompt>"`

## TEST A — Simon's voice memo + structured-output reasoning

**Audio:** `/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav` (14 s)
**Reasoning prompt:** *"Summarize in one sentence what the speaker is testing, then list one risk and one expected outcome."*

### Stage 1 — whisperX transcript

> *"This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works."*

### Stage 2 — Gemma 26B-A4B reasoning

> The speaker is testing the ability of Gemma to transcribe a voice memo processed by MLXVLM.
>
> * **Risk:** The transcription may be inaccurate or fail to capture the nuances of the audio.
> * **Expected Outcome:** An assessment of how well Gemma performs the transcription task.

**Observation:** The model followed the structured-output instruction (one summary sentence + one risk + one expected outcome).

---

## TEST B — Real whispered ASMR clip + emotion-and-topic question

**Audio:** `test-corpus/13-whispered-real.wav` (30 s, real whispered speech extracted from archive.org ASMR)
**Reasoning prompt:** *"Identify the speaker's emotional state and summarize the main topic in one sentence."*

### Stage 1 — whisperX transcript

> *"Yeah, so that kind of sucks, but I'm still going to be making videos and I'm going to pull through whatever **troubles I go through** with my health. I wanted to just say hello to everyone. I wanted to say that I hope everyone is well and, you know, there's a lot of things in the news and current events at the moment"*

### Stage 2 — Gemma 26B-A4B reasoning

> **Emotional State:** Resilient and cautiously optimistic (acknowledging difficulty while maintaining determination).
>
> **Summary:** The speaker is providing a brief update to reassure their audience that they will continue making videos despite ongoing health challenges.

**Observation:** Picked up emotional tone, context (health challenges), and intent (audience reassurance). All targeted, all on-message.

---

## The headline comparison — Phase 2 vs Phase 3 on the same audio

| Approach | Result on TEST B audio |
|---|---|
| **Gemma 4 E4B alone** (Phase 2, F21) | "pull through whatever uh trouble **psychotherapy** with my health" — full lexical hallucination |
| **Two-stage whisperX → Gemma 26B-A4B** (Phase 3, F26) | Correct transcript ("troubles I go through") **+** structured emotional analysis |

The two-stage pipeline avoids Gemma 4 E4B's audio-side limitations (F18 `right→front`, F20 `spoons→spuds`, F21 `troubles→psychotherapy`) by routing audio through Whisper first, and then layers Gemma's reasoning capability on top of clean text.

## Performance summary

| Metric | Value |
|---|---|
| Stage 1 latency (14 s clip) | ~10–25 s wall (whisperX with VAD) |
| Stage 2 latency (200-token reasoning) | ~10–15 s wall |
| Total latency (14 s audio → reasoned answer) | **~30–60 s** |
| Stage 1 peak memory | ~3 GB |
| Stage 2 peak memory | **16.2 GB** (MoE: only 3.8 B params active) |
| Concurrent peak | 16.2 GB (stages sequential, not co-resident) |

## ADR-001b — final draft

| Use case | Recommended | Rationale |
|---|---|---|
| **Audio → text only** | **whisperX** | Phase 1.5/1.6 evidence (F6, F12); ADR-001a |
| **Audio → reasoning over content** | **Two-stage whisperX → Gemma 26B-A4B** | F26: outperforms Gemma 4 E4B alone empirically |
| **Unknown content where false-positives are worse than empties** | **whisperX** OR **Gemma 4 E4B** alone | F19: both produce empty rather than canonical hallucinations |

The original brief framing — "can Gemma replace Whisper on this VM?" — is answered:
- **No**, not for raw transcription (Whisper is materially better, F12 / F18 / F20 / F21).
- **Yes**, for combined audio→reasoning workflows when paired *with* Whisper (F26).
