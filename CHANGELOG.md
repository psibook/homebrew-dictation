# Changelog

All notable changes to the `psibook/dictation` Homebrew tap.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
relative to the `dictation-stack` formula's `version` field.

## [Unreleased]

### Changed (BREAKING — install flow now requires one extra command)
- **Removed `def post_install` from the formula.** The original
  0.1.0 design had `def post_install` invoke `dictate-stack-install`,
  which `uv tool install`s the five Python tools. That writes to
  `~/.cache/uv/` and `~/.local/share/uv/tools/` — both outside the
  Homebrew prefix. **Empirical confirmation on a Tier 2 macOS host
  (`gww@mbp23`, 2026-05-08) that the brew install sandbox returns
  `Operation not permitted (os error 1)` for those writes.** All five
  `uv tool install` calls failed identically; whisperX was never
  installed; T1–T5 then correctly reported "whisperx not found".
- New install flow is **four commands**, not three:
  ```
  brew tap psibook/dictation
  brew install dictation-stack
  dictate-stack-install            # NEW: explicit user step
  dictate-verify
  ```
  `dictate-stack-install` runs in the user's shell, outside the brew
  sandbox, where the user-scope writes are permitted as designed.
- ADR-002 gained a postscript dated 2026-05-08 documenting the
  observed failure, the decision change, and what is and isn't
  preserved by it.
- README Quick Start, the "Install — what each command actually
  does" section, the formula's `caveats` block, and
  `HANDOFF-TO-HOST.md` are all updated to reflect the four-command
  flow and to explain *why* it's four rather than three.

### Fixed
- Formula's `def install` no longer trips `Errno::EPERM @ apply2files`
  on stricter macOS configurations (Tier 2 hosts). Root cause:
  `bin.install tap_root/"bin/foo"` did a move-or-copy-then-remove on
  the tap-side path, and Homebrew's install sandbox grants READ but not
  WRITE access to the tap directory — the source-removal step
  failed with EPERM. Fix: copy tap-side files (`bin/`, `test-fixtures/`,
  `host-tests/`) into the build's staging directory via `cp_r src/. dst/`
  first, then `bin.install Dir["stage_bin/*"]`. Homebrew now operates
  only on staged files it owns. Failure originally observed on
  `gww@mbp23` (Tier 2 macOS); retest required.
- `host-tests/T2-repeat.sh`, `T3-resource.sh`, and `T4-offline.sh` now
  use the shared `require_tool whisperx locate_whisperx` helper rather
  than a generic `log_fail "whisperx not found"`. The helper prints
  actionable next-step instructions (`dictate-stack-install`, the
  PATH check, the README link) when a user-scope tool is missing.

### Added
- Six-test host-side test suite under `host-tests/`:
  T1 smoke, T2 repeat-determinism, T3 RSS budget, T4 HF-offline,
  T5 strict-lenient agreement, T6 `brew test`. Documented in
  `host-tests/TEST-PLAN.md`.
- `host-tests/lib/normalize-paths.sh` post-run filter that rewrites
  `${HOME}` → `$HOME` and `/Volumes/My Shared Files` → `$REMOTE_PATH`
  in captured logs. Has a `--strict` mode that fails on any unhandled
  `/Users/<other>/` or `/Volumes/...` survivor — used in CI to catch
  new path-portability leaks.
- `corpus-results/NON-REPRODUCIBLE.md` banner explaining that the
  inherited VM-side captures are reference history, not reproducible
  via this tap; pointers to the host-tests for what IS reproducible.
- Formula `livecheck` block (auto-detect new whisper.cpp upstream
  releases via GitHub's latest-release strategy).
- Formula `head` block (HEAD installs from `master`).
- Formula multi-step `test do` block — five assertions covering
  script `--help` reachability, fixture SHA verification,
  `whisper-cli` invocation, `dictate-verify --help` reachability,
  and `host-tests/run-all.sh --list` discoverability.

### Changed
- `bin/dictate-stack-install` now resolves `ffmpeg@7`'s lib via
  `brew --prefix ffmpeg@7` rather than the hardcoded
  `/opt/homebrew/opt/ffmpeg@7/lib`. This makes the IFW rpath patch
  work on Intel Macs as well as Apple Silicon.
- `bin/dictate-stack-install` now uses a `python3.*` glob to locate
  IFW's torchcodec dir, rather than hardcoded `python3.13`. Survives
  uv's default Python rolling without code edits.
- `bin/dictate-warmup` similarly uses `brew --prefix ffmpeg@7` for
  `DYLD_FALLBACK_LIBRARY_PATH` rather than `/opt/homebrew/opt/ffmpeg@7/lib`.
- README rewritten with quick-start at the top, "Why this tap"
  rationale (the five sharp edges this tap hides), backend-selection
  table, empirical-PASS-criterion explanation, and full tap layout.
- Formula `caveats` now documents the `host-tests/run-all.sh` path
  alongside the simpler `dictate-verify` invocation.

## [0.1.0] — 2026-05-08

### Added
- Initial release. `Formula/dictation-stack.rb` meta-formula that:
  - depends on `cmake` (build), `ffmpeg`, `ffmpeg@7`, `uv`, `:macos`
  - builds whisper.cpp v1.8.4 from source with Metal enabled
  - installs `whisper-cli`, `dictate-verify`, `dictate-stack-install`,
    `dictate-warmup` into `bin/`
  - stages the test fixture (`demo-audio-for-gemma.wav` + hashes +
    expected transcript) into `pkgshare/`
  - in `def post_install`, runs `dictate-stack-install` to `uv tool
    install` `openai-whisper`, `mlx-whisper`, `whisperx`,
    `insanely-fast-whisper` (with `torch>=2.11`), `mlx-vlm` and apply
    the IFW torchcodec rpath + codesign patch (PLAN.md F5/F27)
- `bin/dictate-verify` — strict transcript-hash equality check against
  the F29 byte-stable reference, with `--lenient` substring fallback.
  Exits 0 on PASS / 1 on FAIL.
- `bin/dictate-stack-install` — idempotent (re)installer with
  `--patch-only` (after `uv tool upgrade` wipes the patch) and
  `--uninstall` modes.
- `bin/dictate-warmup` — pre-pull weights for all six backends.
- `decisions/ADR-002-tap-structure.md` — meta-formula vs per-tool
  trade-off.
- `HANDOFF-TO-HOST.md` — three-command verification runbook for the
  source-contract author handing off to a host operator.
- `LICENSE` — MIT.
- `README.md` — initial install + verify + warmup docs.

### Notes

- The tap is macOS-only (`depends_on :macos`). MLX, MPS, codesign, and
  install_name_tool are all macOS-specific.
- The `def post_install` step writes into user-scope dirs
  (`~/.local/share/uv/tools/`), bending Homebrew convention. This is
  the central trade-off recorded in ADR-002.
