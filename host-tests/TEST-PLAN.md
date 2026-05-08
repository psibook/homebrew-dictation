# Host-side test plan

The `host-tests/` suite validates that `brew install
psibook/dictation/dictation-stack` produced a working dictation stack on
the host machine. Six tests, each derived from a finding in the
`gemma-on-vm` source contract (PLAN.md F1–F32).

## How to run

### All tests, end to end

```bash
host-tests/run-all.sh
```

Captures every test's output (stdout + stderr) under
`host-tests/runs/<timestamp>/`, prints a colour-coded PASS/FAIL summary,
and exits 0 only if every test passed. Wall time on a warm-cached host:
~2 minutes. First run on a cold install: ~10 minutes (whisperX pulls
~3 GB of weights from huggingface.co).

### A subset

```bash
host-tests/run-all.sh T1 T3
host-tests/run-all.sh --list   # show available test names
```

### One test, standalone

```bash
host-tests/T1-smoke.sh
```

Each test is independently runnable and creates its own
`host-tests/runs/<timestamp>-standalone/` directory. Useful for
re-running just the failing one after a fix.

### Strict path-portability scan

```bash
host-tests/run-all.sh --strict
```

After the test suite, scan every captured `*.log` with
`lib/normalize-paths.sh --strict`. Fails if any log contains an
unhandled `/Users/<name>/` or `/Volumes/<...>/` pattern that the
normalizer missed. This catches new path-leak regressions when test
scripts evolve.

## Path normalization (the post-run filter)

Every test pipes its captured output through
[`lib/normalize-paths.sh`](lib/normalize-paths.sh) before saving it as
`host-tests/runs/<timestamp>/<test-id>.log`. Two replacement rules:

| Source pattern | Substituted with |
|---|---|
| `${HOME}` (env value at capture time) | literal `$HOME` |
| `/Volumes/My Shared Files` | literal `$REMOTE_PATH` |

Why: tool stdout, tracebacks, and tool config dumps embed absolute
paths that would otherwise leak the running user's home directory and
any external mount points. The normalized form makes captured logs
shareable across machines (and across this tap's contributors and the
source-contract VM that the corpus-results predate).

The raw pre-normalization output is also saved alongside, as
`<test-id>.raw.log`, for the rare case where the substitution itself
hides useful detail. Inspect or delete those at will — they are not
re-processed by `--strict`.

## The six tests

### T1 — smoke

**Source:** PLAN F29 (whisperX byte-determinism).

**Question:** does `dictate-verify` exit 0 against the bundled fixture?

**Why it exists:** this is the contract's done-criterion in one test. If
T1 PASSes, the formula resolved its system deps, `def post_install` ran
the user-scope `uv tool install` for whisperX, the IFW rpath patch is
intact, the demo fixture is on disk at the bundled location, the
huggingface-hub model pull completed, and whisperX produces the F29
byte-stable transcript hash on this host.

**Failure mode triage:** see [HANDOFF-TO-HOST.md](../HANDOFF-TO-HOST.md).

### T2 — repeat

**Source:** PLAN F29 (whisperX byte-determinism, four-run cross-check).

**Question:** does whisperX produce byte-identical output across two
back-to-back invocations on this host?

**Why it exists:** F29 was demonstrated on the source VM (4 independent
runs all produced the same SHA-256). T2 verifies the property holds on
THIS host. If two runs on the same machine diverge, either:

- the host's faster-whisper dispatch is non-deterministic for reasons
  we didn't catch on the VM (different CPU, different BLAS variant) —
  a finding worth filing back to the source contract; or
- something is wrong with the install (a stale model on one run, or
  the temperature isn't actually 0).

**Pass criterion:** SHA-256 of run-1 output == SHA-256 of run-2 output.
The transcripts themselves are NOT compared to the bundled F29 hash
here — that's T1's job. T2 cares only about cross-run equality.

### T3 — resource

**Source:** PLAN F30 (peak RSS measurements per backend).

**Question:** does whisperX peak under a sane memory budget on this
host?

**Why it exists:** F30 measured whisperX peak RSS at 8.43 GiB on the
source VM (M3 Max paravirtualised). On low-RAM hosts (16 GiB MacBook
Air, base-model Mac mini) headroom matters — if whisperX peaks closer
to system memory, the OS will swap and the F29 byte-stable property may
not hold under pressure.

**Method:** sample summed RSS of whisperX and all descendants every
0.5 s during the run. F31 documented the `lsof -i -p` AND/OR pitfall;
this script avoids it by walking the pgrep tree explicitly.

**Pass criterion:** peak RSS < `BUDGET_GIB` (default 12 GiB). Override:

```bash
BUDGET_GIB=8 host-tests/T3-resource.sh
```

### T4 — offline

**Source:** PLAN F31 (HuggingFace staleness checks during inference).

**Question:** does whisperX still work with `HF_HUB_OFFLINE=1` once the
model is cached?

**Why it exists:** F31 measured 31 socket events on port 443 from
whisperX during a single inference run — those are HF hub staleness
checks. For air-gapped hosts, hosts behind corporate proxies, or simply
faster startup, users want to disable those calls.

**Pre-condition:** whisperX must have been run at least once on this
host (model pulled into HF cache). T1 satisfies this if it ran first.
T4 detects a missing model and reports a pre-condition failure rather
than a content failure.

**Pass criterion:** whisperX exits 0 with `HF_HUB_OFFLINE=1` and
`TRANSFORMERS_OFFLINE=1` set, and produces non-empty output.

### T5 — strict-lenient agreement

**Source:** dictate-verify's own design (--strict vs --lenient modes).

**Question:** do dictate-verify's two pass criteria agree?

**Why it exists:** `dictate-verify` ships two tiers:

- **strict** — exact transcript SHA-256 match against the F29
  reference. Fragile to whisperX version drift, but proves
  byte-for-byte reproducibility.
- **lenient** — substring-presence match (must contain "voice memo",
  an MLXVLM-shaped token, and "Gemma"). Survives small
  segmentation/punctuation drift.

T5 runs both and asserts that at least one passes:

| strict | lenient | meaning | T5 verdict |
|---|---|---|---|
| PASS | PASS | F29 reproducible on this host | PASS |
| FAIL | PASS | whisperX upgraded; content correct | PASS (with warning) |
| PASS | FAIL | dictate-verify or expected.txt is buggy | FAIL |
| FAIL | FAIL | content actually diverged on this host | FAIL |

### T6 — brew test

**Source:** Homebrew's standard contract — every formula carries a
`test do` block, invoked via `brew test`.

**Question:** does `brew test psibook/dictation/dictation-stack` pass?

**Why it exists:** intentionally redundant with T1 (the formula's `test
do` delegates to `dictate-verify`), but exercises a different invocation
surface — Homebrew's sandboxing, environment scrubbing, and audit
harness all wrap `brew test`. If T1 passes but T6 fails, something in
the Homebrew test environment is incompatible with how dictate-verify
resolves its fixture or the whisperX path.

**Pass criterion:** `brew test psibook/dictation/dictation-stack`
exits 0.

## Adding a new test

1. Author `host-tests/T7-yourtest.sh`. Source `lib/common.sh`. Set
   `TEST_ID="T7-yourtest"`. Use `capture_normalized` for any command
   whose output should be saved.
2. Add it to the `ALL_TESTS` array in `run-all.sh` and to the
   `resolve()` switch.
3. Document what it proves and which F-finding it derives from in this
   TEST-PLAN.md.
4. Run with `--strict` to make sure your captures don't introduce new
   leaks.

## Troubleshooting

| Symptom | Most likely cause |
|---|---|
| T1 FAIL, T6 FAIL: "fixture missing" | Tap not installed: `brew install psibook/dictation/dictation-stack` |
| T1 FAIL: "whisperx not found" | `~/.local/bin` not on PATH — `export PATH="$HOME/.local/bin:$PATH"` |
| T1 PASS, T2 FAIL | Real cross-run divergence on this host. File a bug. |
| T3 FAIL: "peak RSS exceeded budget" | Low-RAM host. Run with `BUDGET_GIB=14` or close other apps. |
| T4 FAIL: "model not in HF cache" | Run T1 first to pull the weights, then re-run T4. |
| T5 strict-FAIL + lenient-FAIL | whisperX content actually diverged. Check `runs/<ts>/T5-lenient.log` for the transcript and report. |
| T6 FAIL but T1 PASS | Homebrew sandbox incompatibility — check `runs/<ts>/T6-brew-test.log` |

## Cross-reference

- [`lib/normalize-paths.sh`](lib/normalize-paths.sh) — the post-run
  filter, with `--strict` mode for CI.
- [`lib/common.sh`](lib/common.sh) — shared helpers for fixture/tool
  location and capture-and-normalize.
- [`HANDOFF-TO-HOST.md`](../HANDOFF-TO-HOST.md) — three-command verify
  for the user who just wants `brew install` to work.
- [`decisions/ADR-002-tap-structure.md`](../decisions/ADR-002-tap-structure.md)
  — why this is one meta-formula rather than per-tool formulas.
- [`corpus-results/NON-REPRODUCIBLE.md`](../corpus-results/NON-REPRODUCIBLE.md)
  — note about the historical VM-side captures that share the
  repository.
