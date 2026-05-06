# T2 Repeat-Invocation Report

**Date:** 2026-05-06 15:57:27
**Input:** `/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav`
**Method:** call each backend twice consecutively (warm cache → warm cache).

**Pass criteria:** both runs produce non-empty output AND (for deterministic backends) outputs match byte-for-byte AND run-2 wall ≤ run-1 wall × 1.2.

| Backend | Run 1 | Run 2 | Match | Wall 1 (s) | Wall 2 (s) | Verdict |
|---|---|---|---|---:|---:|---|
| openai-whisper | PASS | PASS | MATCH | 47.26 | 45.39 | PASS |
| mlx-whisper | PASS | PASS | MATCH | 8.19 | 4.07 | PASS |
| whisperx | PASS | PASS | MATCH | 39.57 | 26.91 | PASS |
| whisper-cpp | PASS | PASS | MATCH | 19.88 | 20.24 | PASS |
| ifw | PASS | PASS | MATCH | 36.98 | 29.41 | PASS |
| gemma-e4b | PASS | PASS | MATCH | 12.28 | 8.50 | PASS |

**Overall:** 6 / 6 backends pass.
