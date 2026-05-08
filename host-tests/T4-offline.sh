#!/usr/bin/env bash
# T4-offline.sh — does whisperX still work with HF_HUB_OFFLINE=1?
#
# WHY: F31 (gemma-on-vm) measured 31 socket events on port 443 from
# whisperX during a single inference run — those are HuggingFace hub
# staleness checks (the model is already cached, but whisperX phones
# home to verify its rev). For:
#
#   - air-gapped / strict-network hosts
#   - hosts behind corporate proxies that block CDNs
#   - simply faster startup (no network round-trips)
#
# the user can set HF_HUB_OFFLINE=1 (and TRANSFORMERS_OFFLINE=1) to
# skip those calls entirely. T4 verifies this works AFTER the model
# has been pulled at least once.
#
# Pass criterion: whisperX exits 0 with HF_HUB_OFFLINE=1 set.
#
# Pre-condition: whisperX has been run at least once on this host
# (model must be cached locally). T1 satisfies this if it ran first.

set -uo pipefail
TEST_ID="T4-offline"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

WHISPERX="$(locate_whisperx)" || { log_fail "whisperx not found"; exit 1; }
FIXTURE_DIR="$(locate_fixture_dir)" || { log_fail "fixture dir not found"; exit 1; }
INPUT="$FIXTURE_DIR/demo-audio-for-gemma.wav"

# Pre-check: is the model cached? If not, this test would fail because
# of a missing model rather than the offline flag.
hf_cache="$HOME/.cache/huggingface/hub"
if [ ! -d "$hf_cache" ] || [ -z "$(find "$hf_cache" -maxdepth 4 -name '*faster-whisper-large-v3*' -print -quit 2>/dev/null)" ]; then
  log_warn "faster-whisper-large-v3 not in HF cache; T4 requires a prior whisperX run."
  log_warn "Run T1 first, or:  dictate-verify"
  log_fail "skipping T4 — pre-condition not met"
  exit 1
fi

log_step "Running whisperX with HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1..."

run_offline() {
  local out="$1"
  mkdir -p "$out"
  HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
    "$WHISPERX" "$INPUT" \
      --model large-v3 --task translate \
      --output_dir "$out" --output_format txt \
      --no_align --compute_type float32
}

if capture_normalized T4-offline run_offline "$RUN_DIR/T4-output"; then
  out_txt="$(ls "$RUN_DIR/T4-output"/*.txt 2>/dev/null | head -1 || true)"
  if [ -n "$out_txt" ] && [ -s "$out_txt" ]; then
    log_pass "whisperX runs offline; output written"
    exit 0
  fi
  log_fail "whisperX exited 0 but produced no output"
  exit 1
fi

log_fail "whisperX failed in offline mode; see $RUN_DIR/T4-offline.log"
echo "  Last 10 lines:"
tail -10 "$RUN_DIR/T4-offline.log" | sed 's/^/    /'
exit 1
