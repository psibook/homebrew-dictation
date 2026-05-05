# Real-World Failure Corpus — 5 Additional Test Cases

**Date:** 2026-05-05 14:14
**Task:** `transcribe`
**Backends:** openai-whisper · mlx-whisper · whisperX · whisper.cpp

## Test cases (real-world / refined synthetic)

| # | Test case | Source | Duration | Why it might fail |
|---|---|---|---|---:|
| 10 | Glasgow Scottish accent | [GMU SAA speakerid=82](https://accent.gmu.edu/browse_language.php?function=detail&speakerid=82) | 21.2 s | Rhotic consonants, vowel shifts |
| 11 | Melbourne Australian accent | [GMU SAA speakerid=140](https://accent.gmu.edu/browse_language.php?function=detail&speakerid=140) | 24.3 s | Documented 2026 Mozilla failure case (Whisper) |
| 12 | Mumbai Indian accent | [GMU SAA speakerid=426](https://accent.gmu.edu/browse_language.php?function=detail&speakerid=426) | 21.9 s | Distribution shift, distinctive prosody |
| 13 | Real whispered speech (ASMR) | [archive.org Whispering N00b ASMR](https://archive.org/details/ASMRWhisperingReading8r2ESNzVOOA), 30 s slice from 60 s offset | 30.0 s | Voiceless phonation, no fundamental pitch |
| 14 | Music chord (3-tone C-E-G) + Simon's speech | Synthesized chord overlay | 14.0 s | Harmonic distractor (richer than 440 Hz tone test 06) |

All three accent samples are reading the standard GMU passage:
> *"Please call Stella. Ask her to bring these things with her from the store. Six spoons of fresh snow peas, five thick slabs of blue cheese and maybe a snack for her brother Bob. We also need a small plastic snake and a big toy frog for the kids. She can scoop these things into three red bags and we will go meet her Wednesday at the train station."*

## Outputs

### 10 — Glasgow Scottish

| Backend | Result |
|---|---|
| openai-whisper | "Please call Stella. Ask her to bring these things… **spoons**…" ✅ |
| mlx-whisper | "Please call Stella, ask her to bring…" ✅ (comma instead of period) |
| whisperX | "Please call Stella. …" ✅ |
| whisper.cpp | "Please call Stella. …" ✅ |

**All 4 backends parsed Glasgow Scottish cleanly.** No accent failure. Difference is segmentation only.

### 11 — Melbourne Australian

| Backend | Output of "Six **spoons** of fresh snow peas" |
|---|---|
| openai-whisper | "Six **spurns** of fresh snow peas" 🔴 |
| mlx-whisper | "Six **spurns** of fresh snow peas" 🔴 |
| **whisperX** | "Six **spoons** of fresh snow peas" ✅ |
| whisper.cpp | "Six **spurns** of fresh snow peas" 🔴 |

**🔴 THIS IS THE DOCUMENTED MOZILLA 2026 AUSTRALIAN-ENGLISH FAILURE CASE — REPRODUCED.** 3 of 4 backends mis-hear "spoons" as "spurns" because of Australian vowel shift on the /uː/ phoneme. **WhisperX (faster-whisper backend) is the only one that got it right** — likely because of different decoder hyperparameters / temperature defaults.

### 12 — Mumbai Indian

| Backend | Output |
|---|---|
| openai-whisper | "**please call stella** ask her to bring…" 🟡 (lowercased, no punctuation) |
| mlx-whisper | "Please call Stella. Ask her to bring…" ✅ |
| whisperX | "Please call Stella. Ask her to bring…" ✅ |
| whisper.cpp | "**please call stella** ask her to bring…" 🟡 (lowercased, no punctuation) |

**🟡 Striking formatting divergence on the same model weights.** openai-whisper and whisper.cpp produced fully unpunctuated, lowercased output for the Indian-accented passage; mlx-whisper and whisperX preserved punctuation and case. Text content is otherwise correct (all four heard "spoons" correctly here). The accent didn't break content — but it did trigger a different normalization codepath in 2 of 4 backends.

### 13 — Real whispered ASMR speech

| Backend | Result |
|---|---|
| openai-whisper | Clean transcript of 30 s of whispered narration ✅ |
| mlx-whisper | Same (minor variant: "I want it to" vs "I wanted to") 🟡 |
| whisperX | Same as openai-whisper ✅ |
| whisper.cpp | Same but dropped one word ("there's a things" vs "there's a lot of things") 🟡 |

**Real whispered speech does NOT break Whisper Large-v3.** All 4 backends transcribed the YouTube ASMR speaker's content correctly with only minor word-level errors. The pseudo-whisper synthesis (case 09) was too weak, but real whispered speech is also handled — Whisper's training set evidently includes enough whispered content.

### 14 — 3-note chord overlay + Simon's speech

| Backend | Result |
|---|---|
| openai-whisper | Clean Simon transcript, comma-after-memo (drift) 🟡 |
| mlx-whisper | Clean transcript, missing period after "memo" (run-on) 🟡 |
| whisperX | Clean ✅ |
| whisper.cpp | Clean (Simon-with-period segmentation) ✅ |

**A C-E-G chord doesn't break Whisper.** Same outcome as the simpler 440 Hz tone test (case 06). The encoder is robust to harmonic distractors well above pure-tone complexity. **Real songs with vocals + rhythm + dynamic range may still break it; we did not directly test that.**

## Implications for ADR-001a

**WhisperX is the only backend to correctly transcribe the documented Australian English failure case.** Combined with its silence/short-clip immunity (F6 from the synthetic corpus), this strengthens its case as the default-recommended backend for unknown-content pipelines.

The other three backends — openai-whisper, mlx-whisper, whisper.cpp — share the Australian failure mode despite using ostensibly the same model weights. The faster-whisper / CTranslate2 backend that whisperX uses must be doing something materially different in the decoding pass.

The Mumbai Indian formatting divergence is a separate pipeline concern: any downstream tool expecting consistent capitalization/punctuation will see inconsistent output depending on backend choice and accent.
