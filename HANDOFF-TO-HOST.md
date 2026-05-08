# Handoff: verify on the host

This runbook is the Lieutenant's last-mile step. The tap is published at
`psibook/homebrew-dictation` (PUBLIC, default branch `main`). Run the
following on the host Mac (NOT inside the gemma-on-vm UTM VM — the VM
already has all five Python tools `uv tool install`-ed and re-running
`dictate-stack-install` against them would be a no-op at best and a
clobber at worst).

## Pre-conditions on the host

- macOS arm64 (Apple Silicon).
- Homebrew installed: `brew --version` returns 5.x.
- `gh` CLI authenticated as `psibook` (only needed if you want to inspect
  the repo from the host; not required for the install itself).
- Network reachability to `github.com` and `huggingface.co` over HTTPS.
- ~30 GB free disk (the formula itself is small; the model-weight downloads
  on first run are the bulk).

## The four-command verification

```bash
brew tap psibook/dictation
brew install dictation-stack
dictate-stack-install                 # one-time, user-scope Python tools install
dictate-verify
```

Expected outcomes:

| Step | What happens | Wall time (rough) |
|---|---|---|
| `brew tap psibook/dictation` | clones github.com/psibook/homebrew-dictation into `$(brew --repository)/Library/Taps/psibook/homebrew-dictation/` | <30 s |
| `brew install dictation-stack` | pulls deps, builds whisper.cpp v1.8.4 from source, installs scripts + fixtures into the brew prefix. **Does not** install the Python tools (sandbox-blocked) — the caveats tell you so. | 1–5 min |
| `dictate-stack-install` | runs in your shell (no brew sandbox): `uv tool install`s 5 Python tools, pins `torch>=2.11` for IFW, applies the torchcodec rpath patch, ad-hoc codesigns the dylib | 5–15 min — torchcodec + transformers + faster-whisper are heavy uv installs |
| `dictate-verify` | verifies bundled audio SHA, runs whisperX, compares transcript SHA against the F29 byte-stable reference | 30 s on a warm cache; **first run pulls ~3 GB of whisperX weights from huggingface.co — expect 1–5 min depending on bandwidth** |

PASS criterion (per the contract): **`dictate-verify` exits 0.**

## Why four commands instead of three

Homebrew's install sandbox forbids writes to `~/.cache/uv/` and
`~/.local/share/uv/tools/`. `uv tool install` writes there. So
`def post_install` cannot run `uv tool install` reliably — it
silently fails on stricter macOS configurations (Tier 2 hosts) with
`Operation not permitted (os error 1)`. The fix: split user-scope
work out of `brew install` and require an explicit
`dictate-stack-install` step that runs without the sandbox.

ADR-002 (`decisions/ADR-002-tap-structure.md`) records the original
"atomic install" design, the empirical sandbox-blocked failure on
`gww@mbp23`, and the design change to the four-command flow.

## What to do if any step fails

### `brew install dictation-stack` fails

Most likely a Homebrew dep issue. Run:

```bash
brew doctor
brew update
brew install dictation-stack
```

If the failure is on `cmake -B build` (whisper.cpp source build), you
may need to update Command Line Tools:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select --install
```

### `dictate-stack-install` fails

Re-run it; `uv tool install` is idempotent. If a single tool's install
fails repeatedly, install just that one for diagnostics:

```bash
dictate-stack-install whisperx
```

If the IFW patch step fails specifically:

```bash
dictate-stack-install --patch-only
```

### `dictate-verify` reports "FAIL — whisperx not found"

`dictate-stack-install` either didn't run or it ran but `~/.local/bin`
isn't on your PATH. Check both:

```bash
which whisperx                       # should print ~/.local/bin/whisperx
ls -la ~/.local/bin/whisperx         # should be executable

# If missing, run:
dictate-stack-install

# If present but not on PATH:
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
dictate-verify
```

### `dictate-verify` reports "FAIL — input audio hash mismatch"

The `demo-audio-for-gemma.wav` fixture in `$(brew --prefix)/share/dictation-stack/`
doesn't match the recorded SHA-256. Re-tap:

```bash
brew untap psibook/dictation
brew tap psibook/dictation
brew reinstall dictation-stack
```

### "FAIL — whisperx exited non-zero"

Most likely a transient HuggingFace timeout pulling the 3 GB weights.
Re-run; whisperX caches what it got. If it persists, check the log tail
in the failure output for the exact error (usually a connection reset or
401 on a deprecated model URL).

### "transcript SHA-256 mismatch (strict failed)"

The whisperX install works but produces a different transcript than the
F29 byte-stable reference. Two likely causes:

1. **whisperX upgraded** between the time the reference was captured
   (whisperX 3.8.5 + faster-whisper-large-v3 on 2026-05-06) and now.
   Segmentation, punctuation or whitespace can drift across versions
   while the content stays correct. Re-run with `--lenient`:

   ```bash
   dictate-verify --lenient
   ```

   This passes if the transcript contains "voice memo", an MLXVLM-shaped
   token, and "Gemma" — the same criterion as `tests/smoke.sh` in the
   source contract.

2. **A different host/CPU producing genuinely different output** —
   whisperX's faster-whisper backend is supposed to be deterministic at
   the default temperature (PLAN.md F29 verified this across 4 runs on
   the same VM), but cross-host determinism wasn't tested. If
   `--lenient` also fails, this is a real divergence worth reporting
   back to the source contract.

### "FAIL — IFW patch verify failed"

Run `dictate-stack-install --patch-only` to re-apply the rpath patch:

```bash
dictate-stack-install --patch-only
```

If that still fails, the torchcodec dylib path may have changed in a
new IFW or torchcodec version. Inspect with `otool`:

```bash
torchcodec_dir="$(uv tool dir)/insanely-fast-whisper/lib/python3.13/site-packages/torchcodec"
ls -la "$torchcodec_dir"
otool -l "$torchcodec_dir/libtorchcodec_core7.dylib" | grep -A2 LC_RPATH
```

## Inspect the public repo after publish

```bash
gh repo view psibook/homebrew-dictation --json visibility,defaultBranchRef,description,url
gh api repos/psibook/homebrew-dictation/contents/Formula --jq '.[].name'
```

Expected:
- `visibility: public`
- `defaultBranchRef.name: main`
- `Formula/` contains `dictation-stack.rb`

## Rollback

```bash
dictate-stack-install --uninstall      # remove user-scope Python tools
brew uninstall dictation-stack         # remove formula's prefix-installed bits
brew untap psibook/dictation           # remove the tap clone
rm -rf ~/.cache/huggingface ~/.cache/whisper   # remove model weights (~25 GB)
```

## Provenance

- Source contract: `psibook/gemma-on-vm` (PRIVATE), branch `main` at
  `6d72fbe` ("Phase 3 hardening: T2/T3/T4 PASS, T5 pre-reboot baseline").
- This branch: `feature/brew-tap` forked from `main@6d72fbe` on
  2026-05-08, in the parallel worktree at
  `~/continental/software/cases/gemma-on-vm-brew-tap/`.
- Tap repo: `psibook/homebrew-dictation` (PUBLIC), created 2026-05-08
  via `gh repo create … --public` per BRIEF.md vm-share-bootstrap-precedent.
- Empirical reference for `dictate-verify`: PLAN.md F29 — whisperX is
  byte-deterministic at the default temperature; `dc4ff7e2…6bada` is the
  hash reproduced across T2-repeat run1, T2-repeat run2, T3-resource,
  and T4-egress (4 independent runs on 2026-05-06).
- IFW patch recipe: PLAN.md F5 + F27.
- Tap-structure decision: this tap's `decisions/ADR-002-tap-structure.md`.
