# homebrew-dictation

Homebrew tap for the local audio-translation stack measured in
[`psibook/gemma-on-vm`](https://github.com/psibook/gemma-on-vm) — five Whisper
backends, Gemma 4 multimodal, and a verification script that proves a fresh
install reproduces the empirical PASS criterion.

## What's in the stack

| Component | Source | How it's installed |
|---|---|---|
| `ffmpeg`, `ffmpeg@7` | Homebrew core | `depends_on` |
| `uv`, `cmake` | Homebrew core | `depends_on` |
| `whisper.cpp` v1.8.4 | upstream tarball | built from source with Metal enabled |
| `openai-whisper`, `mlx-whisper`, `whisperx`, `mlx-vlm` | PyPI | `uv tool install` (in `def post_install`) |
| `insanely-fast-whisper` | PyPI | `uv tool install --with "torch>=2.11"` + rpath patch + ad-hoc resign (PLAN.md F5/F27) |

Plus three first-party scripts:

- `dictate-verify` — runs whisperX on a bundled WAV and compares the
  transcript against a hash captured across four independent runs on the
  source VM (the F29 byte-stable reference). Exits 0 / 1.
- `dictate-stack-install` — does the user-scope `uv tool install` work and
  applies the IFW torchcodec rpath patch. Re-runnable; supports
  `--patch-only` (after `uv tool upgrade insanely-fast-whisper` wipes the
  patch) and `--uninstall`.
- `dictate-warmup` — pre-pulls model weights for all six backends so the
  first user-facing call isn't bottlenecked on a 25 GB HuggingFace download.

## Install

```bash
brew tap psibook/dictation
brew install dictation-stack
```

That single `brew install` triggers the full dance:

1. Pulls `ffmpeg`, `ffmpeg@7`, `uv`, `cmake` from Homebrew core.
2. Builds `whisper.cpp` v1.8.4 from source with Metal enabled.
3. Installs `whisper-cli`, `dictate-verify`, `dictate-stack-install`,
   `dictate-warmup` into `$(brew --prefix)/bin`.
4. Stages the test fixture audio + expected transcript into
   `$(brew --prefix)/share/dictation-stack/`.
5. Runs `dictate-stack-install` in `def post_install` — which `uv tool
   install`s the five Python tools and applies the IFW patch.

Add `~/.local/bin` to your `PATH` if it isn't already (most shells include it):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Verify

```bash
dictate-verify
```

This is the contract's done-criterion. It:

1. Verifies the bundled audio's SHA-256 against the recorded value
   (`4bbb06bc…d4735`).
2. Runs `whisperx --model large-v3 --task translate --no_align
   --compute_type float32`.
3. Compares the transcript's SHA-256 against `dc4ff7e2…6bada`, which is
   what the same flags produced on the gemma-on-vm VM across four
   separate runs (PLAN.md F29).

PASS → exit 0. Mismatch → exit 1 with a diff. If your whisperX version
is newer and the segmentation drifted but the content is correct, re-run
with `--lenient` to fall back to substring-presence matching (the smoke.sh
standard from the source contract).

## Warmup (optional)

`dictate-verify` works fine on a cold install — whisperX will pull its
~3 GB weights from HuggingFace on first run. To pre-pull weights for
*every* backend (~25 GB) so they're all instantly usable:

```bash
dictate-warmup                  # all six backends + Gemma 4 E4B (~25 GB)
dictate-warmup --whisper-only   # skip Gemma 4, ~9 GB
```

## After `uv tool upgrade insanely-fast-whisper`

Any `uv tool install --reinstall …` (or `uv tool upgrade`) wipes the
torchcodec rpath patch. Re-apply it:

```bash
dictate-stack-install --patch-only
```

This is recipe-noted in `PLAN.md F27` of the source contract.

## Why is the post-install touching `~/.local/share/uv/tools/`?

Homebrew formulas conventionally write only into the Homebrew prefix.
This formula deliberately bends that convention: `def post_install`
runs `uv tool install` and `install_name_tool`, both of which land
in user-scope dirs.

`decisions/ADR-002-tap-structure.md` records the trade-off:

- A standard-conventions formula would either (a) split each Python
  tool into a separate Homebrew formula with `Language::Python::Virtualenv`
  resources (huge author burden, six independent version pins), or
  (b) leave the Python installs as a separate command for the user
  (no atomic install).
- The Lieutenant's brief asks for a single `brew install` that produces
  the same stack measured in the source contract. That requires either
  a meta-formula with user-scope post-install (chosen — option A), or
  per-tool formulas that each have the same wart (option B, multiplied
  by six).

The cost is paid in two places:

1. `brew uninstall dictation-stack` does NOT remove the user-scope tools.
   To remove them: `dictate-stack-install --uninstall`.
2. The HuggingFace cache (`~/.cache/huggingface/`) and openai-whisper
   cache (`~/.cache/whisper/`) hold ~25 GB of model weights and are
   never auto-removed. Clean manually if desired:
   ```bash
   rm -rf ~/.cache/huggingface ~/.cache/whisper
   ```

## What the empirical PASS criterion is

PLAN.md F29 documents that whisperX, run with the flags above, produces
**byte-identical** output across four independent invocations
(T2-repeat run1, T2-repeat run2, T3-resource, T4-egress) on the same
14-second WAV. The bundled `expected.sha256` is the hash that those
four runs all produced.

If `dictate-verify` reports PASS, you have empirical evidence that:

- All deps resolved (ffmpeg, ffmpeg@7, uv).
- Whisper.cpp built and ran (smoke pass via `whisper-cli`, indirect).
- whisperX is installed and on PATH.
- faster-whisper-large-v3 weights downloaded successfully from HuggingFace.
- Metal / MPS path is functional on this host.
- The full pipeline produces the same transcript as the source VM.

## Tap layout

```
homebrew-dictation/
├── Formula/
│   └── dictation-stack.rb        ← the meta-formula
├── bin/
│   ├── dictate-verify
│   ├── dictate-stack-install
│   └── dictate-warmup
├── test-fixtures/
│   ├── demo-audio-for-gemma.wav             (1.3 MB, 14 s, 48 kHz mono PCM)
│   ├── demo-audio-for-gemma.input.sha256
│   ├── demo-audio-for-gemma.expected.txt
│   ├── demo-audio-for-gemma.expected.sha256
│   └── PROVENANCE.md
├── decisions/
│   └── ADR-002-tap-structure.md
├── README.md                     (this file)
└── LICENSE                       (MIT)
```

## Origin

This tap is the host-side packaging of the gemma-on-vm contract
(`psibook/gemma-on-vm`), authored on the parallel-worktree branch
`feature/brew-tap` from `main@6d72fbe`. The empirical findings (F1–F32),
the IFW patch recipe, and the audio fixture all come from that contract;
this tap exists to transfer the working stack to a host Mac in one
`brew install`.

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
