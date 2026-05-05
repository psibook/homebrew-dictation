# gemma-on-vm — PLAN.md

**Suite:** Software | **Client:** Lieutenant | **Started:** 2026-05-05
**Repo:** `~/continental/software/cases/gemma-on-vm/`
**Status:** Phase 1 (Whisper installs) substantially complete; Phase 2 (Gemma) deferred.

---

## Scope

Install, run, and verify local AI models on the Continental VM (Apple M3 Max paravirtualised under UTM, 8 cores, 64 GiB RAM, 112 GiB free disk). The contract covers two model families:

1. **Whisper** — audio → text / translate; multiple distributions
2. **Gemma** — text + multimodal LLM; planned for a later phase

Originally Gemma-only. Scope broadened 2026-05-05 after the Lieutenant supplied a 14-second WAV (`demo-audio-for-gemma.wav`, 48 kHz mono PCM) and asked for VM-side audio→translation today. Research found Whisper Large-v3 outperforms Gemma 4 E4B for raw transcription/translation accuracy. One contract covers both — sister ADRs **001a** (Whisper variant) and **001b** (Gemma variant).

Routing chosen: option **(I)** — extend the contract rather than open a sibling.

---

## Phases

### Phase 0 — Reconnaissance ✅ COMPLETE

- VM resource picture verified (M3 Max paravirtualised, 8 cores, 64 GiB RAM, 112 GiB free).
- Egress confirmed (HF 0.1 s, GitHub ~10 s — slow but reachable).
- Metal probe initial signal: empty (`system_profiler SPDisplaysDataType` returned nothing).
- Metal definitively confirmed at runtime in Phase 1 (whisper.cpp): `Apple Paravirtual device`, `MTL0 backend`.

### Phase 1 — Whisper installs ✅ SUBSTANTIALLY COMPLETE

**Goal:** install all 5 free Whisper distributions with `large-v3`-class models, smoke-test each, build a comparison harness so the Lieutenant can run failing-input tests.

| # | Backend | Install | Smoke (translate) | Wall (warm) | Notes |
|---|---|---|---|---:|---|
| 1 | **openai-whisper** (PyTorch) | ✅ | ✅ | 42.79 s | Reference; CPU only |
| 2 | **mlx-whisper** (MLX/Metal) | ✅ | ✅ | **3.74 s** | Fastest warm; weights cached |
| 3 | **whisperX** (faster-whisper + VAD) | ✅ | ✅ | 37.73 s | `--diarize` is a flag, not k=v |
| 4 | **whisper.cpp** (C++ / GGML, Metal) | ✅ | ✅ | 22.76 s | Confirmed Metal under UTM |
| 5 | **insanely-fast-whisper** (transformers) | ⚠️ Installed but doesn't run | ❌ | n/a | torchcodec/PyTorch ABI mismatch — see Finding F5 |

Comparison harness: `tools/whisper-compare.sh` runs all five against one input, captures wall time, dumps side-by-side outputs.

### Phase 2 — Gemma 4 install — DEFERRED

Pending Lieutenant decision on Gemma 4 E2B (smaller, 10 GB) vs E4B (larger, more capable). Required reading: `BRIEF.md` and the in-conversation research findings (Gemma 2/3 27B have no audio; only Gemma 4 E2B/E4B can do audio; mlx-vlm Issue #903 status check required before install).

### Phase 3 — Test cases (per BRIEF.md T1–T5)

- **T1 cold smoke** ✅ (per-backend, all 4 working backends pass on demo file)
- **T2 repeat invocation** — pending; harness already supports this
- **T3 resource bound** (memory under documented budget) — pending
- **T4 HTTPS-only egress** (vm-ops policy) — pending; spot-checked during installs (HF + GitHub HTTPS only)
- **T5 reboot survival** — pending

---

## Decisions (ADRs)

Empty placeholders to be filled as decisions firm up:

- **ADR-001a (Whisper variant)** — pending; need result of Phase 1 comparison on harder inputs
- **ADR-001b (Gemma variant)** — pending Phase 2 (E2B vs E4B vs the others)
- **ADR-002 (Whisper runtime per use case)** — pending after failure-input testing
- **ADR-003 (quantization)** — pending
- **ADR-004 (Metal under UTM)** — drafting

---

## Findings

### F1 — Metal IS exposed under UTM (2026-05-05)

The brief's open Q4 (Metal passthrough) is **resolved YES**.

Evidence:
- whisper.cpp `cmake -B build` reported `-- Metal framework found / -- Including METAL backend`.
- whisper.cpp at runtime: `ggml_metal_init: found device: Apple Paravirtual device / picking default device: Apple Paravirtual device / using MTL0 backend`.
- mlx-whisper ran without Metal-related errors and achieved 3.74 s warm-cache wall on a 14 s audio clip — performance consistent with Metal acceleration.

Performance under paravirtualised Metal on this VM:
- whisper.cpp (Metal, large-v3): 14 s audio → 22.76 s wall (~0.6× real-time, cold encode 6.3 s + decode 15.9 s).
- mlx-whisper (MLX/Metal, large-v3): 14 s audio → 3.74 s wall warm (3.7× real-time); 36.79 s first run (incl. 14 s of model download).

### F2 — All 5 candidate Whisper distros install on Python 3.13 via `uv tool`

`uv tool list` shows: openai-whisper v20250625, mlx-whisper v0.4.3, whisperx v3.8.5, insanely-fast-whisper v0.0.15. whisper.cpp builds from source via cmake into `tools/whisper.cpp/build/bin/`.

### F3 — `ffmpeg@7` is required for any tool that bundles `torchcodec`

`torchcodec` ships pre-compiled dylibs binding to `libavutil.56–59` (FFmpeg 4–7). The system default ffmpeg is now 8.x with `libavutil.60`. Workaround: `brew install ffmpeg@7` and either set `DYLD_FALLBACK_LIBRARY_PATH` (often stripped by SIP through wrapper binaries) or patch the dylib's rpath with `install_name_tool -add_rpath /opt/homebrew/opt/ffmpeg@7/lib …` followed by ad-hoc `codesign --force --sign - …`.

### F4 — Working backends produce textually-identical outputs but with subtle segmentation differences on the demo file

| Backend | Text |
|---|---|
| openai-whisper / mlx-whisper / whisperX | `…with MLXVLM. Just going to see…` |
| whisper.cpp | `…with MLXVLM, just going to see…` |

Same words; different sentence boundary inferred at the same audio position. This is exactly the kind of variation worth studying under harder (noisy / accented / overlapping-speech) inputs — see Phase 1 follow-up.

### F5 — `insanely-fast-whisper` cannot load on this stack (two compounding bugs)

Bug 5a — torchcodec wants `libavutil.56–59`; system has `libavutil.60`. Workaround feasible (ffmpeg@7 + rpath patch + ad-hoc resign).

Bug 5b — Even with 5a fixed, `libtorchcodec_core7.dylib` references the symbol `_torch_dtype_float4_e2m1fn_x2` from `libtorch_cpu.dylib`, not present in the installed PyTorch 2.10. This is a **torchcodec/PyTorch ABI mismatch**. Fixing this would require either (a) upgrading PyTorch to a version that exports the FP4 datatype symbol (likely PyTorch ≥ 2.11.0 — check), or (b) downgrading torchcodec, or (c) switching the audio loader. Decision: not worth the time; insanely-fast-whisper is a transformers-pipeline wrapper and adds little novel coverage vs the other four distributions.

**Status:** marked known-fail in `tools/whisper-compare.sh`. Lieutenant has 4 functional backends, sufficient for failure-mode comparison.

---

## Open questions

- ADR-001a: which Whisper backend(s) are the Lieutenant's defaults for which use case (translation, dictation, diarised transcription, fastest-warm, on-disk reproducibility)?
- ADR-001b: Gemma 4 E2B or E4B for Phase 2?
- Phase 3 timing: when to formalise T2–T5 against all backends?
- Should `insanely-fast-whisper` be removed from the install set or kept with the known-fail flag for revisit later?

---

## Test cases

| ID | Status | Notes |
|---|---|---|
| T1 cold smoke | ✅ 4/5 pass | demo-audio-for-gemma.wav; insanely-fast-whisper fails |
| T2 repeat | pending | re-run via `tools/whisper-compare.sh` |
| T3 resource bound | pending | RSS via `ps -axo rss,comm` during run |
| T4 HTTPS-only egress | pending (informally OK) | weights pulled from HF / GitHub over HTTPS |
| T5 reboot survival | pending | re-run harness after VM reboot |

---

## Session log

- **2026-05-05 11:03–11:30 (active session, 27 min so far)** — kickoff session opened from parking-lot deposit. Planning Q1 → gemma-on-vm chosen over Skills P1-CRITICAL. Q2 (variant) opened then preempted by audio file delivery → research established Whisper > Gemma for raw audio→translation → contract scope broadened. All 5 Whisper distributions installed; 4 working; Metal confirmed under UTM; comparison harness written and validated; PLAN/INSTALL/smoke files in this commit.
