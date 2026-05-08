# NON-REPRODUCIBLE — VM-side capture, kept for reference

**These artifacts are NOT reproducible from this tap.** They were
captured on the source contract's VM (`gemma-on-vm`, Apple M3 Max
paravirtualised under UTM) on 2026-05-05 and 2026-05-06. They are
preserved here for reference — to anchor the F-findings cited in
`README.md`, `decisions/ADR-002-tap-structure.md`,
`HANDOFF-TO-HOST.md`, `host-tests/TEST-PLAN.md`, etc. — but they are
read-only history.

## What's actually here

- `2026-05-05-114430-transcribe/` — Phase 1 corpus, 9 synthetic failure
  cases × 4 working backends (transcribe task)
- `2026-05-05-141400-accents/` — Phase 1.6 real-world accent samples,
  5 cases × 4 backends
- `2026-05-05-150750-gemma4-E4B/` — Phase 2 Gemma 4 E4B run on the
  same 14 inputs
- `2026-05-05-151700-podcast-bed/` — Phase 2.5 music-with-speech
  corpus
- `2026-05-05-162400-two-stage/` — Phase 3 two-stage Whisper→Gemma
  pipeline
- `2026-05-05-163500-ifw-revival/` — Phase 4 insanely-fast-whisper
  after the rpath patch
- `2026-05-06-155228-T2-repeat/` — Phase 6 T2 four-run determinism
  evidence (the empirical basis for F29)
- `2026-05-06-155856-T3-resource/` — Phase 6 T3 RSS samples
- `2026-05-06-160932-T4-egress/` — Phase 6 T4 socket-event audit
- `2026-05-06-161249-T5-pre-reboot/` — Phase 6 T5 pre-reboot baseline

## Why "non-reproducible" from this tap

Three reasons:

1. **The harness scripts that produced these were VM-side.** They
   lived in the source contract's `tests/` directory and hardcoded
   `/Users/dev/.local/bin/<tool>` and
   `/Volumes/My Shared Files/receive-from-vm/<file>.wav`. Neither
   path exists on a host Mac.

2. **The 16-case corpus inputs are not packaged in this tap.** The
   tap bundles only one fixture (`test-fixtures/demo-audio-for-gemma.wav`)
   — the one `dictate-verify` and `host-tests/T1`–`T6` exercise. The
   other 15 cases (silence, codec-degraded, accents, podcast bed,
   etc.) live in the source contract's `test-corpus/` directory; they
   are research inputs, not production fixtures, and their inclusion
   here would multiply tap size 6× without adding host-test value.

3. **The captures embed VM-specific paths in their content.** Most
   `.log` files contain absolute paths like
   `/Users/dev/.local/share/uv/tools/...torchcodec/libtorchcodec_core7.dylib`
   from PyTorch / torchcodec import error tracebacks. These are honest
   captures of what whisperX printed at run time on the source VM —
   editing them would falsify history. We preserve them as-is and let
   the path-normalization filter
   (`host-tests/lib/normalize-paths.sh`) handle the user-facing display
   when the artifacts are referenced.

## What IS reproducible from this tap

The host-runnable test suite at `host-tests/`:

- T1 reproduces the **F29 byte-stable transcript hash**
  (`dc4ff7e2…6bada`) on the host. `corpus-results/2026-05-06-155228-T2-repeat/`
  is the four-run evidence; T1 is the host-side reproduction.
- T2 reproduces the **whisperX cross-run determinism property** on
  the host.
- T3 reproduces the **F30 RSS measurement** on the host (with a
  configurable `BUDGET_GIB` since host RAM varies).
- T4 reproduces the **F31 HF_HUB_OFFLINE behaviour** on the host.

If you want to compare your host's measurements against the source-VM
captures here, run `host-tests/run-all.sh` and look in
`host-tests/runs/<timestamp>/`.

## Cross-references

- Source contract repo: `psibook/gemma-on-vm` (PRIVATE).
- F-findings index: see this contract's `PLAN.md` (also archived in
  this tap as inherited from `main@6d72fbe`).
- Why these aren't sanitized: see
  `host-tests/lib/normalize-paths.sh` — the filter is for
  *new* captures, not for back-editing historical evidence.
