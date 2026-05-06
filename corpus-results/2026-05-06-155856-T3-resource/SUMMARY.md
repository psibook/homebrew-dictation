# T3 Resource-Bound Report

**Date:** 2026-05-06 16:01:23
**Input:** `/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav` (14 s, 1.3 MiB)
**Method:** sample `ps -o rss=` over the backend's process tree every 0.5 s; report peak.
**VM budget:** 64 GiB total RAM.

| Backend | Peak RSS (MiB) | Peak RSS (GiB) | rc | % of 64 GiB |
|---|---:|---:|---:|---:|
| openai-whisper | 9081 | 8.87 | 0 | 13.9% |
| mlx-whisper | 3597 | 3.51 | 0 | 5.5% |
| whisperx | 8635 | 8.43 | 0 | 13.2% |
| whisper-cpp | 4339 | 4.24 | 0 | 6.6% |
| ifw | 3446 | 3.37 | 0 | 5.3% |
| gemma-e4b | 16131 | 15.75 | 0 | 24.6% |
| gemma-26b-a4b | 14668 | 14.33 | 0 | 22.4% |
