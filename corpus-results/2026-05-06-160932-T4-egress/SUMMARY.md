# T4 HTTPS-Only Egress Report

**Date:** 2026-05-06 16:09:32

## 1. vm-ops firewall reference

Per CASE-BOARD.md (vm-ops, SECURE 2026-04-24): firewall State=2, PF rules
loaded, SSH/HTTP blocked outbound, HTTPS (port 443) allowed.
This makes ALL successful weight downloads necessarily HTTPS.

## 2. Weight provenance audit

Cached model directories under `~/.cache/huggingface/hub/`:

| Cache directory | HuggingFace repo (HTTPS) |
|---|---|
| `models--Systran--faster-whisper-large-v3` | https://huggingface.co/Systran\/faster-whisper-large-v3 |
| `models--google--gemma-4-E4B-it` | https://huggingface.co/google\/gemma-4-E4B-it |
| `models--mlx-community--whisper-large-v3-mlx` | https://huggingface.co/mlx-community\/whisper-large-v3-mlx |
| `models--openai--whisper-large-v3` | https://huggingface.co/openai\/whisper-large-v3 |
| `models--unsloth--gemma-4-26b-a4b-it-UD-MLX-4bit` | https://huggingface.co/unsloth\/gemma-4-26b-a4b-it-UD-MLX-4bit |
| `tools/whisper.cpp/models/ggml-large-v3.bin` | https://huggingface.co/ggerganov/whisper.cpp |

All weights trace to `huggingface.co` (HTTPS-only host). Verified by
name; the PF firewall would have dropped any non-HTTPS download path.

## 3. Inference-time socket activity (cached weights)

Each backend launched on the demo file; `lsof -a -i -n -P -p <tree>`
polled every 0.5 s during the run. Loopback (127.0.0.1, ::1, localhost)
filtered out. Counts split by destination port:

- **non-443** = non-loopback connections on any port other than 443 (must be 0 for PASS).
- **to-443** = non-loopback connections on port 443 (HF staleness check on cached weights — informational).

**Pass criteria:** non-443 == 0 AND rc == 0.

| Backend | rc | non-443 | to-443 | Verdict |
|---|---:|---:|---:|---|
| openai-whisper | 0 | 0 | 0 | PASS |
| mlx-whisper | 0 | 0 | 5 | PASS |
| whisperx | 0 | 0 | 31 | PASS |
| whisper-cpp | 0 | 0 | 0 | PASS |
| ifw | 0 | 0 | 30 | PASS |
| gemma-e4b | 0 | 0 | 12 | PASS |

**Overall:** 6 / 6 backends pass.
