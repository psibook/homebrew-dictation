# INSTALL.md — Whisper variants on Continental VM

Reproducible install of the 5 Whisper distributions covered by gemma-on-vm Phase 1, on macOS arm64 (works on bare metal Apple Silicon and on UTM with Metal paravirtualised).

## Prerequisites

- macOS arm64 (verified on Darwin 24.4.0, M3 Max paravirtualised under UTM)
- `uv` (Python project manager) — `curl -LsSf https://astral.sh/uv/install.sh | sh`
- `brew` (Homebrew)
- Xcode Command Line Tools — `xcode-select --install`
- ~15 GiB free disk for `large-v3` weights across all backends
- HTTPS network access to `github.com` and `huggingface.co`

## 1. ffmpeg (system + ffmpeg@7 for torchcodec compatibility)

```bash
brew install ffmpeg          # current; provides libavutil.60
brew install ffmpeg@7        # provides libavutil.59 — needed by torchcodec
```

## 2. openai-whisper

```bash
uv tool install --python 3.13 openai-whisper
```

First-run download: ~2.9 GB `large-v3.pt` to `~/.cache/whisper/`.

CLI: `whisper`. Smoke:
```bash
whisper FILE.wav --model large-v3 --task translate --output_dir DIR --output_format txt
```

## 3. mlx-whisper (Apple Silicon / Metal)

```bash
uv tool install --python 3.13 mlx-whisper
```

First-run download: ~3 GB MLX-format weights from `mlx-community/whisper-large-v3-mlx` to HuggingFace cache.

CLI: `mlx_whisper`. Note dash-flags (`--output-dir`, `--output-format`). Smoke:
```bash
mlx_whisper FILE.wav --model mlx-community/whisper-large-v3-mlx \
  --task translate --output-dir DIR --output-format txt
```

## 4. whisperX (faster-whisper backend + VAD + alignment)

```bash
uv tool install --python 3.13 whisperx
```

CLI: `whisperx`. Note: `--no_align` is a flag (no value); `--diarize` is also a flag (don't pass `False`). Smoke:
```bash
whisperx FILE.wav --model large-v3 --task translate \
  --output_dir DIR --output_format txt \
  --no_align --compute_type float32
```

## 5. whisper.cpp (C++ / GGML, Metal-capable)

```bash
mkdir -p tools && cd tools
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build                                # auto-detects Metal; reports "Metal framework found"
cmake --build build -j --config Release
bash ./models/download-ggml-model.sh large-v3 # ~3.1 GB ggml-large-v3.bin
```

Binary: `tools/whisper.cpp/build/bin/whisper-cli`. Smoke (note: requires 16 kHz mono PCM input):
```bash
ffmpeg -y -i FILE.wav -ar 16000 -ac 1 -f wav input-16k.wav
tools/whisper.cpp/build/bin/whisper-cli \
  -f input-16k.wav \
  -m tools/whisper.cpp/models/ggml-large-v3.bin \
  --translate -of output -otxt
```

## 6. insanely-fast-whisper — FUNCTIONAL with two patches (2026-05-05)

```bash
# Force torch >= 2.11 to get the _torch_dtype_float4_e2m1fn_x2 symbol
# that torchcodec needs from libtorch_cpu:
uv tool install --python 3.13 --reinstall --with "torch>=2.11" insanely-fast-whisper

# Patch torchcodec dylib to find ffmpeg@7's libavutil.59 (ffmpeg 8 ships
# libavutil.60, which torchcodec 0.7 doesn't bind to):
torchcodec_dir=/Users/dev/.local/share/uv/tools/insanely-fast-whisper/lib/python3.13/site-packages/torchcodec
install_name_tool -add_rpath /opt/homebrew/opt/ffmpeg@7/lib "$torchcodec_dir/libtorchcodec_core7.dylib"
codesign --force --sign - "$torchcodec_dir/libtorchcodec_core7.dylib"
```

**Two formerly-blocking bugs (see PLAN.md F5, F27):**

1. **`torchcodec` ↔ `ffmpeg` version mismatch.** torchcodec 0.7 ships dylibs for libavutil.56–59 (ffmpeg 4–7); system has ffmpeg 8 / libavutil.60. The rpath patch + ad-hoc resign above directs the dynamic loader to ffmpeg@7's libavutil.59.

2. **`torchcodec` ↔ `PyTorch` ABI mismatch.** Resolved by upgrading torch to ≥ 2.11.0, which exports the `_torch_dtype_float4_e2m1fn_x2` symbol that torchcodec needs.

**Important:** any subsequent `uv tool install --reinstall …` will WIPE the rpath patch. Re-apply the `install_name_tool` + `codesign` commands above after any reinstall.

CLI: `insanely-fast-whisper`. Smoke:
```bash
insanely-fast-whisper \
  --file-name FILE.wav \
  --model-name openai/whisper-large-v3 \
  --task transcribe \
  --device-id mps \
  --transcript-path output.json
```

**Status:** functional. Sits 2nd on the failure-corpus leaderboard behind whisperX (8 ✅ / 4 🔴 across 16 cases). See ADR-001a.

## Verification

Run the comparison harness on a sample WAV:
```bash
./tools/whisper-compare.sh /path/to/sample.wav translate
```

Or the smoke test on the bundled demo (if `demo-audio-for-gemma.wav` is in `/Volumes/My Shared Files/receive-from-vm/`):
```bash
./tests/smoke.sh
```

## Disk footprint (weights only)

| Distribution | Storage location | Approx size |
|---|---|---|
| openai-whisper large-v3 | `~/.cache/whisper/large-v3.pt` | 2.9 GB |
| mlx-whisper large-v3 | `~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx/` | ~3 GB |
| whisperX (faster-whisper) | `~/.cache/huggingface/hub/models--Systran--faster-whisper-large-v3/` | ~3 GB |
| whisper.cpp ggml-large-v3 | `tools/whisper.cpp/models/ggml-large-v3.bin` | 3.1 GB |
| insanely-fast-whisper (would-be transformers cache) | `~/.cache/huggingface/hub/models--openai--whisper-large-v3/` | ~3 GB |

**Total: ~15 GB.**

## Network policy compliance (vm-ops)

All weight pulls go to `huggingface.co` (HTTPS). whisper.cpp model script uses `huggingface.co` as well. whisper.cpp clone uses `github.com` (HTTPS). All within vm-ops HTTPS-allowed policy; HTTP/SSH egress is blocked and not used.
