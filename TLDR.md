# TL;DR — install, verify, use

Four commands. macOS Apple Silicon. ~30 GB free disk. Network for the
first-run weight downloads only — fully local thereafter.

```bash
brew tap psibook/dictation
brew install dictation-stack          # builds whisper.cpp, installs scripts + fixtures
dictate-stack-install                 # one-time: uv tool install + IFW patch
dictate-verify                        # PASS = stack works end-to-end
```

Why four commands and not three: `brew install` runs inside Homebrew's
sandbox, which forbids writes to `~/.cache/uv/` and
`~/.local/share/uv/tools/` (where `uv tool install` writes). So the
user-scope step is split out and runs in your normal shell, no sandbox.

After `dictate-verify` exits 0, the stack is ready. Pick a recipe:

| You want… | Run this |
|---|---|
| English audio → English text | `whisperx FILE.wav --model large-v3 --task transcribe --output_format txt --no_align --compute_type float32` |
| Non-English audio → English text | same as above with `--task translate` |
| Audio → Spanish/Mandarin/etc. | two-stage: pipe whisperX output into `mlx_vlm.generate --model google/gemma-4-E4B-it --prompt "Translate to Spanish"` |
| Audio → reasoning (summarize, classify, Q&A) | `mlx_vlm.generate --model google/gemma-4-E4B-it --audio FILE.wav --prompt "your task"` |
| Single C++ binary, no Python | `whisper-cli -f input-16k.wav -m ggml-large-v3.bin --translate -of out -otxt` |
| Diarisation (who spoke when) | `whisperx FILE.wav --diarize --hf_token "$HF_TOKEN"` |
| Word-level timestamps for captions | `whisperx FILE.wav` (drop `--no_align`) |
| Run the full host-side test suite (T1–T6) | `$(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh` |
| Pre-pull all model weights (~25 GB) | `dictate-warmup` |
| Save 16 GB by skipping Gemma 4 | `dictate-warmup --whisper-only` |
| Re-apply IFW rpath patch after `uv tool upgrade` | `dictate-stack-install --patch-only` |
| Uninstall everything | `dictate-stack-install --uninstall` then `brew uninstall dictation-stack` |

## Sharp edges (the things this tap hides for you)

- `torchcodec` 0.7 binds against `libavutil.59` but Homebrew's `ffmpeg`
  ships `libavutil.60`. Without `ffmpeg@7` + an `install_name_tool
  -add_rpath` patch, `insanely-fast-whisper` silently fails.
- `torchcodec` references `_torch_dtype_float4_e2m1fn_x2` from
  `libtorch_cpu.dylib` — only present in PyTorch ≥ 2.11.
- `uv tool install --reinstall` (or `uv tool upgrade`) wipes the
  rpath patch; re-apply with `dictate-stack-install --patch-only`.
- `whisperx`'s `--no_align` and `--diarize` are flags (no values).
  `--compute_type` defaults to `float16` on some hosts; `float32`
  is the choice that produces the byte-stable transcripts this tap
  references.

## Picking a backend

| Priority | Pick |
|---|---|
| Best accuracy on unknown audio | `whisperx` (default) |
| Speed on Apple Silicon | `mlx_whisper` |
| Single binary, no Python | `whisper-cli` |
| transformers-pipeline integration | `insanely-fast-whisper` |
| Reasoning over audio content | two-stage `whisperx` → `mlx_vlm.generate` (Gemma 4) |
| Cross-checking baseline | `whisper` (OpenAI's CPU reference) |

## When something fails

- `dictate-verify` says "whisperx not found" → run `dictate-stack-install`.
- `dictate-verify` says "transcript SHA-256 mismatch" → try
  `dictate-verify --lenient`. If lenient passes, your whisperX is a
  newer version and segmentation drifted while content is correct.
- After `uv tool upgrade insanely-fast-whisper` → run
  `dictate-stack-install --patch-only` to re-apply the rpath patch.
- `brew install` fails on `cmake -B build` → update Command Line
  Tools: `sudo rm -rf /Library/Developer/CommandLineTools && sudo
  xcode-select --install`.

## Want more

- [README.md](README.md) — full rationale, backend-selection details,
  the empirical PASS-criterion explanation, badges, etc.
- [HANDOFF-TO-HOST.md](HANDOFF-TO-HOST.md) — runbook with deep-dive
  failure-mode triage.
- [host-tests/TEST-PLAN.md](host-tests/TEST-PLAN.md) — what each of
  T1–T6 proves and why.
- [decisions/ADR-002-tap-structure.md](decisions/ADR-002-tap-structure.md)
  — why this is one meta-formula, plus the 2026-05-08 postscript on
  why the install is four commands and not three.
- [CHANGELOG.md](CHANGELOG.md) — release history.
