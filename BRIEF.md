# gemma-on-vm — Contract Brief

**Dispatched from:** Platinum/sonata-bumper-2026 session, 2026-05-05
**Suite of execution:** Software
**Client:** Lieutenant
**Status:** PARKED — message-board deposit, awaiting kickoff in a fresh Software-suite session
**Resume pointer:** open the new session in `~/continental/software/cases/gemma-on-vm/` (after the setup commands at the bottom of this brief)
**Priority:** TBD at kickoff — the planning interview's Question 1 should weigh this against the existing Software P1 rows (Skills P1-CRITICAL, iphone-dictation P1)

---

## What this is

A Software-suite contract to install, run, and verify Google's **Gemma** open-weights model on the Continental VM. Goal is a working local LLM the Lieutenant can prompt from the command line (and ideally call from scripts), with the runtime, model variant, and quantization captured as ADRs and the install captured as a runbook.

## Why now

The Lieutenant requested it 2026-05-05 from the Platinum suite. Cross-suite request was rerouted via the message-board path (no coin spent, no Rule 2 violation). The actual case opens in the Software suite.

## VM resource picture (captured 2026-05-05)

| Item | Value |
|---|---|
| OS | macOS (Darwin 24.4.0) |
| Architecture | arm64 — Apple M3 Max (Virtual), virtualised under UTM |
| Cores | 8 |
| RAM | 64 GiB |
| Free disk on `/` | 112 GiB |
| Network policy (per vm-ops) | HTTPS allowed, HTTP/SSH blocked outbound; firewall State=2 |
| Shared filesystem (per vm-ops) | VirtIO with `send-to-vm` / `receive-from-vm` couriers — usable for transferring downloaded model weights from the host if the VM's egress is restricted |

**Implication:** any Gemma variant in current production (Gemma 2 2B/9B/27B, Gemma 3, CodeGemma, Recurrent Gemma) can fit comfortably. Quantization is a quality decision, not a memory one.

## Runtime survey (Tool-Research-First per Taste Profile Pref 1)

The kickoff session **must complete this survey before writing any install scripts** and record findings as ADR-002. Candidates:

| Runtime | Fit on macOS arm64 VM | Notes |
|---|---|---|
| **Ollama** | Native arm64 binary, single-command install (`brew install ollama` or `curl ... \| sh`), `ollama pull gemma2:9b` style. Uses llama.cpp under the hood with Metal acceleration. **Likely the ergonomic default.** | Question: does Metal acceleration pass through the UTM virtualised GPU? If not, falls back to CPU — still workable on M3 Max cores but slower. |
| **llama.cpp** | Native; lower-level than Ollama. GGUF quantizations. | Worth it only if Ollama can't fit a need (custom quant, server flag the Lieutenant requires, etc.). |
| **MLX / mlx-lm** | Apple-Silicon-native. Excellent on bare-metal M-series; **uncertain under UTM virtualisation** — Metal/MLX on a virtualised GPU is the open question. | Test before committing. If it works, often the fastest path on M-series. |
| **HuggingFace `transformers`** | Works on macOS arm64 via PyTorch MPS backend (or CPU fallback). Heaviest dependency footprint. | Good if the Lieutenant wants Python-level control or LoRA fine-tuning later. Overkill for inference-only. |
| **vLLM** | Linux/CUDA-first; **does not target macOS arm64**. | Rule out. |

**State the chosen runtime and the rejection reasons in ADR-002.**

## Model variant choice (ADR-001)

To be decided in the planning interview. Options on a 64 GiB VM:

| Variant | Approx. memory (Q4_K_M) | Use cases |
|---|---|---|
| Gemma 2 2B | ~2 GiB | Cheap, instant; fine for autocomplete-tier work. |
| Gemma 2 9B | ~6 GiB | The pragmatic default. Good general chat/code quality. |
| Gemma 2 27B | ~17 GiB | Best quality of the Gemma 2 line; comfortably fits. |
| Gemma 3 (if released stable as of 2026-05-05) | varies | Verify availability and license at kickoff. |
| CodeGemma 7B | ~5 GiB | Code-focused. |
| Recurrent Gemma 2B | ~2 GiB | Niche; unusual architecture. |

**Memory budget is not the binding constraint.** Quality vs. latency is.

## Anticipated artifacts

- `PLAN.md` — case plan, Phase-by-Phase
- `ADR-001-gemma-variant.md` — chosen variant + rejection reasons
- `ADR-002-runtime.md` — chosen runtime + rejection reasons
- `ADR-003-quantization.md` — chosen quant level if applicable
- `INSTALL.md` — runbook (so this is reproducible after a VM rebuild)
- `tests/smoke.sh` — repeatable smoke test
- Optional: a wrapper script (`gemma "prompt"`) so invocation is one word

## Test cases

- **T1 — Cold smoke.** From a fresh shell, invoke the chosen runtime with a simple prompt; receive a coherent ≤500-token reply.
- **T2 — Repeat.** Same prompt twice; second invocation succeeds (no daemon crash, no model-load failure).
- **T3 — Resource bound.** During T1, the VM stays under a memory budget recorded in ADR-003.
- **T4 — Network policy honoured.** Initial model pull succeeds over HTTPS; no attempt to use blocked ports (verify with `lsof` or `nettop` during pull).
- **T5 — Reboot survival.** After VM reboot, runbook steps reproduce the working state.

## Open questions for the planning interview

1. **Variant?** Gemma 2 9B as the pragmatic default, or something else?
2. **Runtime?** Ollama as the ergonomic default, or do you want a deliberate Tool-Research pass first?
3. **Use case?** Interactive chat at the terminal, scripted automation (`gemma "..."` in pipelines), HTTP API for other tools to call, or all three?
4. **Metal passthrough?** Do you know whether UTM is exposing GPU/Metal to this VM, or is that a thing we'll discover in T1?
5. **Egress preference.** Pull weights directly from HuggingFace/Ollama-registry on the VM, or stage on the host and ferry through `send-to-vm/`?

## Setup commands (run at start of kickoff session)

```bash
# 1. Create the case directory and initialise the repo:
mkdir -p ~/continental/software/cases/gemma-on-vm
cd ~/continental/software/cases/gemma-on-vm
git init
git branch -m main

# 2. Optional — create a private remote (no need to push immediately):
gh repo create psibook/gemma-on-vm --private --source=. --remote=origin

# 3. Copy the brief into the case:
cp ~/continental/parking/gemma-on-vm/BRIEF.md ./

# 4. First commit:
git add BRIEF.md
git commit -m "Open contract from parking-lot deposit (2026-05-05)"

# 5. Open Claude.app → Code tab → Select folder → choose this directory.
#    The session will then be filed in the correct bucket
#    (per claude-session-hygiene Phase 1 discipline).
```

## Verbatim Charon prompt for the kickoff session

Paste this into the new session as the first message:

> Charon, I am opening the **gemma-on-vm** contract in the **Software** suite. The full brief is at `BRIEF.md` (root of this repo). Please run the planning interview — five questions, one at a time. Question 1 should weigh this contract against the existing Software-suite P1 rows (Skills P1-CRITICAL and iphone-dictation P1) before proceeding. The brief lists five open questions ready to seed Questions 2–5.

## Notes for the kickoff Charon

- **Tool Research First (Pref 1).** Do the runtime survey before writing install scripts. State what you found, what you ruled out, and why. ADR-002 is the deliverable.
- **Reframe Don't Iterate (Pref 2).** If the first runtime fails twice, change the runtime — not the flags.
- **Precision With Evidence (Pref 3).** Record memory and latency numbers for T1, not impressions.
- **One Issue One Session (Pref 5).** Open a GitHub Issue for Phase 0 (variant + runtime selection) before writing code. Every commit references the Issue.
- **Tests Required (Pref 6).** T1–T5 above. Smoke + repeat + resource + network + reboot. All five must run from `tests/smoke.sh` (or equivalent) with a single command.
- **vm-ops constraints.** HTTPS allowed; HTTP/SSH blocked. Verify model-pull traffic stays on HTTPS — flag if a runtime tries anything else.
- **claude-session-hygiene Phase 1 discipline.** Launch the kickoff Claude session from inside `~/continental/software/cases/gemma-on-vm/`, not from a sibling directory, so the JSONL files land in the right bucket. `/rename` and clean `/exit` at the end.

## Deposited

2026-05-05 from Platinum/sonata-bumper-2026 (a cross-suite request rerouted via the message board). Free — no coin spent.
