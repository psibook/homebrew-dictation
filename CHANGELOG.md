# Changelog

All notable changes to the `psibook/dictation` Homebrew tap.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
relative to the `dictation-stack` formula's `version` field.

## [Unreleased]

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
