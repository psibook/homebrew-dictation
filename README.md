# homebrew-dictation

A Homebrew tap that installs a fully-local audio→text + audio→reasoning
stack on macOS in one command, then proves it works with a bundled
verification script and a six-test host-side suite.

[![macOS](https://img.shields.io/badge/macOS-arm64-blue)](#)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Apple Silicon — Metal](https://img.shields.io/badge/Apple_Silicon-Metal_native-brightgreen)](#)
[![No cloud calls](https://img.shields.io/badge/cloud-zero-success)](#)

```bash
brew tap psibook/dictation
brew install dictation-stack
dictate-verify     # must exit 0
```

That's it. After `dictate-verify` reports PASS, you have:

- **`whisper-cli`** — Metal-accelerated whisper.cpp v1.8.4
- **`whisperx`** — VAD-pre-filtered, accent-robust transcription (the recommended default)
- **`whisper`** — OpenAI's reference CPU implementation
- **`mlx_whisper`** — fastest on Apple Silicon (3.7× real-time on a M3 Max)
- **`insanely-fast-whisper`** — transformers-pipeline-friendly batch ASR (with the torchcodec rpath patch already applied)
- **`mlx_vlm.generate`** — Gemma 4 multimodal LLM for audio→reasoning

…all six on your machine, no API keys, no per-call cost, and no cloud
round-trip. Plus `dictate-verify`, `dictate-stack-install`,
`dictate-warmup`, and a six-test host-side test suite at
`$(brew --prefix dictation-stack)/share/dictation-stack/host-tests/`.

## Why this tap

Installing each of these tools by hand on a Mac is **not the obvious
five-minute job it sounds like.** Some of the sharp edges this tap
hides:

| The edge | What goes wrong without this tap |
|---|---|
| `torchcodec` 0.7 binds against `libavutil.59` | Modern Homebrew's `ffmpeg` ships `libavutil.60`. `insanely-fast-whisper` silently can't load. The fix is `brew install ffmpeg@7` plus an `install_name_tool -add_rpath` and an ad-hoc `codesign --force --sign -` on `libtorchcodec_core7.dylib`. The tap does this for you. |
| PyTorch < 2.11 lacks `_torch_dtype_float4_e2m1fn_x2` | `torchcodec` references that symbol. Without the symbol, IFW import-fails. The tap pins `torch>=2.11` in the `uv tool install --with` clause. |
| `uv tool install --reinstall` wipes the rpath patch | If you ever upgrade IFW, the patch goes away. The tap ships `dictate-stack-install --patch-only` so you re-apply it in one command. |
| `whisperX` defaults that silently degrade quality | `--no_align` is a flag (no value), `--diarize` is a flag (no value), `--compute_type` defaults to `float16` on some hosts, etc. The tap's `dictate-verify` and `host-tests/T1` use the validated `--task translate --no_align --compute_type float32` combination measured to be reproducible across runs. |
| Whether Metal works on your Mac | `whisper.cpp` builds with `-DGGML_METAL=ON`; `mlx-*` is Metal-native by virtue of MLX. Verified to work even under UTM paravirtualisation. |
| Choosing the right backend for a given task | `whisperX` for accuracy, `mlx-whisper` for speed, `whisper.cpp` for single-binary reproducibility, IFW for transformers-pipeline integration, two-stage `whisperX → Gemma 4` for audio→reasoning. The README's [comparison table](#which-backend-when) makes the choice once. |

The tap's empirical reference (the byte-stable transcript hash that
`dictate-verify` checks) was measured across **four** independent
whisperX runs on the source contract's VM and is the install's
done-criterion. See [the evidence section](#the-empirical-pass-criterion).

## Which backend, when

| You care about | Pick | Quick rationale |
|---|---|---|
| **Accuracy on unknown audio** | `whisperx` | 12 of 16 test cases clean. The only backend that handles silence, sub-1 s clips, and Australian English correctly. |
| **Speed on Apple Silicon** | `mlx_whisper` | 3.74 s on a 14 s clip warm cache (~3.7× real-time) on M3 Max. |
| **Single binary, no Python** | `whisper-cli` | Just `whisper-cli`, an FFmpeg pipe, and a GGML weight file. |
| **transformers-pipeline integration** | `insanely-fast-whisper` | Drops into `pipeline("automatic-speech-recognition", …)`. |
| **Reasoning over audio content** (summarise, classify, answer) | Two-stage `whisperx → mlx_vlm.generate` (Gemma 4) | Whisper alone can't reason; Gemma 4 alone is bad at audio. The two-stage stack beats both alone. |
| **Translate non-English audio to English** | `whisperx --task translate` | All Whispers translate-to-English natively; `--task translate` is the right flag. |
| **Translate to a non-target language (Spanish, Mandarin, etc.)** | Two-stage with `mlx_vlm.generate --prompt "Translate to <lang>"` | Whisper can't target non-English; Gemma 4 can be prompted multilingually. |
| **Diarisation (who spoke when)** | `whisperx --diarize` | Uses pyannote.audio; needs a free HF token for the diarisation model. |
| **Reference / debugging baseline** | `whisper` | OpenAI's slow CPU PyTorch reference; useful for cross-checking the others. |

A more elaborate version of this table — Consumer-Reports-style with
Harvey balls and 15 criteria — lives in the source contract's
[`docs/CONSUMER-REPORT.md`](docs/CONSUMER-REPORT.md).

## Install — what `brew install` actually does

```
brew tap psibook/dictation
brew install dictation-stack
```

Behind the scenes:

1. Pulls `cmake`, `ffmpeg`, `ffmpeg@7`, `uv` from Homebrew core.
2. Downloads whisper.cpp v1.8.4 source tarball (SHA-256 pinned).
3. Builds `whisper-cli` (and optional `whisper-server`) with
   `-DGGML_METAL=ON` — Metal acceleration enabled.
4. Stages `dictate-verify`, `dictate-stack-install`, `dictate-warmup`
   into `$(brew --prefix)/bin`.
5. Stages the test fixture (1.3 MB demo WAV + hashes + expected
   transcript) and the six-test host-side suite into
   `$(brew --prefix dictation-stack)/share/dictation-stack/`.
6. In `def post_install`, runs `dictate-stack-install`, which:
   a. `uv tool install`s the five Python tools
   b. Pins `torch>=2.11` for IFW (PLAN F27)
   c. Applies the IFW torchcodec rpath patch + ad-hoc codesign
   d. Verifies the patch with `otool -l`

Wall time on a fast connection: 5–15 minutes (most of it is the
torchcodec, transformers, and faster-whisper Python wheels). Disk:
~1 GB for the formula prefix + a 25 GB HuggingFace cache that fills
the first time each backend is exercised.

## Verify — three pass-criteria, increasing rigor

```bash
dictate-verify             # strict: F29 byte-stable hash match
dictate-verify --lenient   # substring presence: tolerates whisperX version drift
host-tests/run-all.sh      # full six-test suite (T1..T6)
```

For the full suite (recommended after a fresh install):

```bash
$(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh
```

See [`host-tests/TEST-PLAN.md`](host-tests/TEST-PLAN.md) for the
rationale behind each test, what it proves, and how to add new ones.

### The empirical PASS criterion

The bundled `test-fixtures/demo-audio-for-gemma.expected.sha256` is
`dc4ff7e23a04ac6b0051882858dec69be5e070343db496d5d1c21d42c6c7bada`,
the SHA-256 of the whisperX `--task translate` output for
`demo-audio-for-gemma.wav` on the source contract's VM. That hash was
verified **byte-identical across four independent runs** (T2-repeat
run1, T2-repeat run2, T3-resource, T4-egress) on 2026-05-06 — the
empirical foundation of PLAN.md F29 ("whisperX is byte-deterministic
at the default temperature").

`dictate-verify` reproduces that hash on your host. PASS = stack works
end-to-end + you have empirical reproducibility on your machine.

If your whisperX version is newer and segmentation/punctuation drifted,
strict will fail but `--lenient` (substring presence — must contain
"voice memo", an MLXVLM-shaped token, "Gemma") will pass.
[`host-tests/T5-strict-lenient.sh`](host-tests/T5-strict-lenient.sh)
runs both and asserts they agree.

## Warmup — pre-pull weights for offline use

```bash
dictate-warmup                  # all six backends + Gemma 4 (~25 GB)
dictate-warmup --whisper-only   # skip Gemma 4 (~9 GB)
```

After `dictate-warmup`, the stack works fully offline. To stay offline
across whisperX restarts, set:

```bash
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
```

The `host-tests/T4-offline.sh` test verifies this works.

## After `uv tool upgrade insanely-fast-whisper`

```bash
dictate-stack-install --patch-only
```

Any `uv tool install --reinstall` or `uv tool upgrade` wipes the
torchcodec rpath patch. The `--patch-only` mode re-applies it without
re-running the `uv tool install` for everything else.

## Uninstall

```bash
dictate-stack-install --uninstall    # remove user-scope Python tools
brew uninstall dictation-stack       # remove formula's prefix-installed bits
brew untap psibook/dictation         # remove the tap clone
rm -rf ~/.cache/huggingface ~/.cache/whisper   # ~25 GB of model weights
```

The two-step removal exists because `def post_install` writes into
user-scope dirs (`~/.local/share/uv/tools/`) — see
[ADR-002](decisions/ADR-002-tap-structure.md) for the trade-off.

## Is this for you?

**Yes if you want:**
- A reproducible local dictation/transcription/translation pipeline on macOS
- An empirically-grounded "which backend should I use" answer
- Air-gappable or low-latency local inference
- One `brew install` and an obvious done-criterion (`dictate-verify`)

**No if you:**
- Need real-time streaming ASR (try `whisper-streaming` or `Distil-Whisper` instead)
- Run on Linux (this is macOS-only — ffmpeg@7 on macOS, MLX, codesign, install_name_tool)
- Want the smallest possible install (use `brew install whisperx` directly via uv tool — but you'll lose the F29 reproducibility guarantee + the IFW patch)

## Tap layout

```
homebrew-dictation/
├── Formula/
│   └── dictation-stack.rb        ← the meta-formula
├── bin/
│   ├── dictate-verify            ← strict + lenient end-to-end test
│   ├── dictate-stack-install     ← (re)installs Python tools + IFW patches
│   └── dictate-warmup            ← optional pre-pull of all weights
├── host-tests/
│   ├── run-all.sh                ← top-level runner (T1..T6)
│   ├── T1-smoke.sh               ← dictate-verify smoke
│   ├── T2-repeat.sh              ← whisperX byte-stability across runs
│   ├── T3-resource.sh            ← peak RSS budget
│   ├── T4-offline.sh             ← HF_HUB_OFFLINE=1 works
│   ├── T5-strict-lenient.sh      ← dictate-verify mode agreement
│   ├── T6-brew-test.sh           ← `brew test dictation-stack` passes
│   ├── lib/
│   │   ├── normalize-paths.sh    ← post-run path-portability filter
│   │   └── common.sh             ← shared helpers
│   └── TEST-PLAN.md              ← what each test proves and why
├── test-fixtures/
│   ├── demo-audio-for-gemma.wav             (1.3 MB, 14 s, 48 kHz mono PCM)
│   ├── demo-audio-for-gemma.input.sha256
│   ├── demo-audio-for-gemma.expected.txt
│   ├── demo-audio-for-gemma.expected.sha256
│   └── PROVENANCE.md
├── decisions/
│   └── ADR-002-tap-structure.md  ← meta-formula vs per-tool trade-off
├── corpus-results/               ← non-reproducible VM-side captures (kept for reference)
│   └── NON-REPRODUCIBLE.md
├── HANDOFF-TO-HOST.md            ← three-command verification runbook
├── CHANGELOG.md
├── README.md                     (this file)
└── LICENSE                       (MIT)
```

## License

MIT — see [LICENSE](LICENSE).

Component licenses (all installed by this tap):

| Component | License |
|---|---|
| whisper.cpp | MIT |
| openai-whisper | MIT |
| mlx-whisper | MIT |
| whisperx | BSD-2-Clause |
| insanely-fast-whisper | Apache 2.0 |
| mlx-vlm | MIT |
| Gemma 4 weights (downloaded by mlx-vlm) | Gemma Terms of Use |
| Whisper Large-v3 weights | MIT (OpenAI release) |

Every component is free for personal and commercial use, runs on your
hardware, and never phones home for inference.
