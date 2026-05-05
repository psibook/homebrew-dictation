# Failure-Corpus Comparison Report

**Date:** 2026-05-05 11:44:30  
**Task:** `transcribe`  
**Backends:** openai-whisper · mlx-whisper · whisperX · whisper.cpp (insanely-fast-whisper omitted, see PLAN.md F5)

| # | Test case | Expected difficulty |
|---|---|---|
| 01 | Silence (30 s) | Hallucination trigger |
| 02 | 8 kHz phone-quality of Simon's clip | Below 16 kHz training distribution |
| 03 | Codec round-trip (6 kbps Opus) of Simon's clip | Severe spectral degradation |
| 04 | 600 ms clip | Mel-spec context too thin |
| 05 | JFK canonical | Clean baseline |
| 06 | Music (440 Hz tone) + Simon's speech | Encoder gets distracted by harmonics |
| 07 | Simon × Simon offset 2 s (speaker overlap) | No diarisation; conflates |
| 08 | Pink noise + Simon (low SNR) | Severe noise robustness |
| 09 | Pseudo-whispered Simon | Voiceless phonation lacks pitch cues |

## Results

### 01-silence-30s

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 16.75 | you  |
| mlx-whisper | 3.46 | you  |
| whisperx | 21.70 |  |
| whisper-cpp | 10.67 |  Thank you.  |

### 02-phone-quality-8k

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 37.87 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| mlx-whisper | 3.26 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisperx | 29.94 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisper-cpp | 18.72 |  This right here is a quick voice memo. I want to try it out with MLXVLM, just going to see if it can be transcribed by Gemma and how well that works.  |

### 03-codec-degraded-roundtrip

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 34.40 | This right here is a quick voice memo. I want to try it out with NLXVLM, just going to see if it can be transcribed by Gemma and how well that works.  |
| mlx-whisper | 3.14 | This right here is a quick voice memo. I want to try it out with MLSVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisperx | 31.52 | This right here is a quick voice memo. I want to try it out with NLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisper-cpp | 21.78 |  This right here is a quick voice memo. I want to try it out with NLXVLM, just going to see if it can be transcribed by Gemma and how well that works.  |

### 04-very-short-600ms

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 17.82 | Thank you.  |
| mlx-whisper | 2.88 | Thank you.  |
| whisperx | 18.40 |  |
| whisper-cpp | 9.14 |  Thank you.  |

### 05-jfk-canonical

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 28.61 | And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country.  |
| mlx-whisper | 3.19 | And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country.  |
| whisperx | 28.45 | And so, my fellow Americans, ask not what your country can do for you. Ask what you can do for your country.  |
| whisper-cpp | 18.22 |  And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country.  |

### 06-music-and-speech

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 37.01 | This right here is a quick voice memo, I want to try it out with MLXVLM, just going to see if it can be transcribed by Gemma and how well that works.  |
| mlx-whisper | 3.07 | This right here is a quick voice memo I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisperx | 30.40 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisper-cpp | 23.79 |  This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |

### 07-speaker-overlap

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 36.78 | This right here is a quick voice memo, I want to try it out with Gemma, just going to see if it can be transcribed by Gemma and how well that works.  |
| mlx-whisper | 3.54 | This right here is a quick voice memo. I want to try it out with Gemma. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisperx | 31.49 | This right here is a quick voice memo. I want to try it out with Gemma. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisper-cpp | 23.80 |  This right here is a quick voice memo. This right here is a quick voice memo. I want to try it out with Gemma. Just going to see if it can be transcribed by Gemma and how well that works.  |

### 08-pink-noise-overlay

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 18.18 | Thank you.  |
| mlx-whisper | 2.74 | Thank you.  |
| whisperx | 25.88 | Yes, ma'am.  |
| whisper-cpp | 9.63 |  this  |

### 09-pseudo-whispered

| Backend | Wall (s) | Output |
|---|---:|---|
| openai-whisper | 37.79 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| mlx-whisper | 3.30 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisperx | 30.37 | This right here is a quick voice memo. I want to try it out with MLXVLM. Just going to see if it can be transcribed by Gemma and how well that works.  |
| whisper-cpp | 21.73 |  This right here is a quick voice memo. I want to try it out with MLXVLM, just going to see if it can be transcribed by Gemma and how well that works.  |

