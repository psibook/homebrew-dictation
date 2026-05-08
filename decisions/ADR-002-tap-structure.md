---
ADR: 002
Title: Tap structure — single meta-formula `dictation-stack`
Status: Accepted
Date: 2026-05-08
Suite: Software
Branch: `feature/brew-tap`
---

## Context

The `gemma-on-vm` contract delivered a six-backend audio→text + audio→reasoning
stack on the Continental VM (PLAN.md Phases 1–6, F1–F32). The Lieutenant now
wants the same stack installable on a host Mac via Homebrew, with a verification
script that proves a fresh install reproduces the empirical PASS criterion.

The package universe to deliver:

| Component | Source | Install vector |
|---|---|---|
| `ffmpeg`     | Homebrew core | `depends_on` |
| `ffmpeg@7`   | Homebrew core | `depends_on` (the `libavutil.59` carrier — see PLAN F3) |
| `uv`         | Homebrew core | `depends_on` |
| `cmake`      | Homebrew core | `depends_on => :build` |
| `whisper.cpp` v1.8.4 | upstream tarball | built from source in `def install` |
| `openai-whisper`   | PyPI | `uv tool install` in `def post_install` |
| `mlx-whisper`      | PyPI | `uv tool install` in `def post_install` |
| `whisperx`         | PyPI | `uv tool install` in `def post_install` |
| `insanely-fast-whisper` | PyPI | `uv tool install --with "torch>=2.11"` + rpath patch (PLAN F5/F27) |
| `mlx-vlm`          | PyPI | `uv tool install` in `def post_install` |

Plus three first-party scripts (`dictate-verify`, `dictate-stack-install`,
`dictate-warmup`) and a test fixture (`demo-audio-for-gemma.wav`, 1.3 MB,
SHA-256 `4bbb06bc…d4735`).

## Decision

**One meta-formula `dictation-stack.rb` that depends on the Homebrew-shipped
system tools and pulls the Python tools in `def post_install`.**

No per-tool formulas. No `whisperx.rb`, no `mlx-whisper.rb`, no `mlx-vlm.rb`.
The user runs one command:

```
brew tap psibook/dictation
brew install dictation-stack
dictate-verify        # exits 0 on PASS
```

## Trade-off considered

| Aspect | (A) Meta-formula only — chosen | (B) Per-tool formulas + meta |
|---|---|---|
| Author effort | One `.rb` file | Six `.rb` files + linkage |
| User flexibility | All-or-nothing — `dictation-stack` installs everything | Cherry-pick — `brew install psibook/dictation/whisperx` alone |
| Empirical guarantee | Atomic install gives the **corpus-tested combination** (F1–F32) | User can assemble incompatible component versions; F12/F26 results no longer hold |
| Update churn | Single version pin to track | Six independent version pins |
| Idempotent retry | One `def post_install`; partial failure leaves user-scope state inconsistent | Per-tool blocks, easier to retry individually |
| `brew uninstall` semantics | Removes infra (whisper.cpp, scripts, fixtures); user-scope `uv tool` installs persist as orphans | Same orphan problem, six-fold |

The two options share the "uv tool persists after brew uninstall" wart;
neither solves it cleanly. That is a Homebrew convention violation either way
(see Consequences below).

## Reasons (A) wins

1. **Empirical guarantee.** PLAN.md is a corpus of 16 audio cases × 6 backends
   = 96 measurements. Those measurements are about a specific combination of
   versions running on a specific OS. A user who installs only `whisperx` and
   pairs it with their own Gemma 4 build is no longer using the stack the
   contract measured. Atomic install keeps the corpus claims load-bearing.

2. **The audience is one Lieutenant, not a marketplace.** Per-tool flexibility
   is a feature for a public tap with diverse downstreams. This tap exists to
   transfer one specific stack to one specific host. Optimise for that case.

3. **`uv tool install` in `def post_install` is the unusual part.** Doing it
   six times across six formulas multiplies the unusualness. Doing it once,
   in one place, with one set of caveats, is easier to audit and easier to
   revisit if Homebrew conventions evolve.

4. **Reversibility.** Adding per-tool formulas later is mechanical; ripping
   them out once they exist is harder. Start with the smallest correct thing.

## Consequences

### Positive

- One install command. One uninstall command (with the orphan caveat).
- Post-install caveats document exactly what is in user-scope and how to
  remove it manually if `brew uninstall` is run.
- IFW rpath patch (PLAN F5/F27) lives in one place — `def post_install` of
  `dictation-stack.rb` — which is the same place that runs the `uv tool
  install --reinstall --with "torch>=2.11"` step that necessitates re-applying
  the patch.

### Negative — known and documented

- **Homebrew convention violation: writing to user-scope dirs.** A standard
  Homebrew formula installs only into `HOMEBREW_PREFIX`. This formula's
  `def post_install` writes into `~/.local/share/uv/tools/` (uv tool dir).
  The README and `caveats` block both call this out. Consequence: `brew
  uninstall dictation-stack` does not remove the Python tools; the user
  must run `dictate-stack-install --uninstall` (provided) to clean
  user-scope state.

- **Less granularity.** A user who wants just `mlx-whisper` cannot get it
  from this tap without also installing the other four backends + Gemma 4
  + whisper.cpp. Mitigation: that user can `uv tool install mlx-whisper`
  directly without this tap. The tap exists for the integrated stack.

- **Single point of failure.** If one `uv tool install` fails in
  `def post_install`, the whole formula's post-install fails. Mitigation:
  the install script is idempotent and re-runnable via `dictate-stack-install`
  — the user can retry without re-running `brew install`.

### Reversibility

If a future requirement demands per-tool installs:

1. Author per-tool formulas under `Formula/whisperx.rb`, etc.
2. Refactor `dictation-stack.rb` to `depends_on` each per-tool formula.
3. Existing users transition cleanly via `brew reinstall dictation-stack`.

The decision today does not foreclose that path.

## Cross-references

- PLAN.md F3 (`ffmpeg@7` requirement)
- PLAN.md F5, F27, F28 (IFW rpath patch)
- PLAN.md F26, F29 (deterministic transcript hash on demo file — basis for
  `dictate-verify`'s strict-equality check)
- INSTALL.md §6 (the patches this formula automates)
- BRIEF.md (this branch's prompt)
- This tap's `Formula/dictation-stack.rb` (implementation)
- This tap's `bin/dictate-verify` (the F29-grounded verification check)

---

## Postscript — 2026-05-08, design change

The "Negative Consequences" section above flagged
> **Homebrew convention violation: writing to user-scope dirs.**
> A standard Homebrew formula installs only into `HOMEBREW_PREFIX`.
> This formula's `def post_install` writes into
> `~/.local/share/uv/tools/` (uv tool dir).

Empirical evidence on a Tier 2 macOS host (`gww@mbp23`, 2026-05-08)
confirmed this is **not just unconventional — it is actually
prohibited** by Homebrew's install sandbox. `uv tool install` failed
with:

```
error: Failed to initialize cache at `/Users/gww/.cache/uv`
  Caused by: failed to open file `/Users/gww/.cache/uv/sdists-v9/.git`:
  Operation not permitted (os error 1)
```

Five `uv tool install` calls failed identically. Cause: the brew
sandbox grants writes only to the formula's prefix (and the build's
staging dir during `def install`). `~/.cache/uv/` and
`~/.local/share/uv/tools/` are outside that allow-list, so any
syscall that opens a file there for write returns EPERM.

### Decision change

Remove `system bin/"dictate-stack-install"` from `def post_install`.
The formula's responsibility ends at installing the prefix-scope bits
(scripts, fixtures, host-tests/, the source-built `whisper-cli`).
The user-scope `uv tool install` work moves to an explicit user step:

```
brew tap psibook/dictation
brew install dictation-stack       # was: did everything (and failed)
dictate-stack-install              # NEW: user runs this in their shell
dictate-verify
```

Run from the user's shell, `dictate-stack-install` operates without
the brew sandbox and the original install logic is unchanged.

### What this preserves

- Empirical guarantee atomicity (Reason 1 in the original decision)
  is unaffected — `dictate-stack-install` still installs all five
  Python tools as a coherent unit.
- The IFW rpath patch (the other reason for the post_install hook)
  still runs, just one command later.
- Per-tool flexibility is still NOT offered (per the original
  Reason 4, "Reversibility — adding per-tool formulas later is
  mechanical").

### What it costs

- A four-command Quick Start instead of three. Documented prominently
  in `README.md`, in `HANDOFF-TO-HOST.md`, and in the formula's
  `caveats` block (which Homebrew prints right after `brew install`).
- A second-pass error mode: if the user reads only the README's
  Quick Start and skips the caveats, `dictate-verify` will fail with
  "whisperx not found" rather than just working. The error message
  in `bin/dictate-verify` already directs the user to
  `dictate-stack-install`, so recovery is one command away.

### Status

- 2026-05-08: Original failure observed on `gww@mbp23`.
- 2026-05-08: Design change applied; `def post_install` removed,
  caveats rewritten, README and HANDOFF-TO-HOST updated, this
  postscript added. CHANGELOG entry under [Unreleased].
- Retest pending on `gww@mbp23`.
