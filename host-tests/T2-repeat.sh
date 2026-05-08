#!/usr/bin/env bash
# T2-repeat.sh — does whisperX produce byte-identical output across two
# back-to-back invocations on this host?
#
# WHY: F29 (gemma-on-vm) showed whisperX is byte-deterministic at the
# default temperature when run on the source VM. T2 verifies this
# property holds on THIS host. If two runs diverge, either:
#   (a) the host's faster-whisper dispatch is non-deterministic for
#       reasons we didn't catch on the VM (different CPU, different
#       BLAS) — finding worth filing.
#   (b) something is wrong with the install (whisperX is reading a
#       stale model on one run, or temperature isn't actually 0).
#
# Pass criterion: run-1 and run-2 transcripts have the same SHA-256.
# The transcripts themselves are NOT compared to the bundled F29 hash
# here — that's T1's job. T2 cares only about cross-run equality.

set -uo pipefail
TEST_ID="T2-repeat"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

WHISPERX="$(locate_whisperx)" || {
  log_fail "whisperx not found"
  exit 1
}
FIXTURE_DIR="$(locate_fixture_dir)" || {
  log_fail "fixture dir not found"
  exit 1
}
INPUT="$FIXTURE_DIR/demo-audio-for-gemma.wav"

run_whisperx() {
  local out="$1"
  mkdir -p "$out"
  "$WHISPERX" "$INPUT" \
    --model large-v3 --task translate \
    --output_dir "$out" --output_format txt \
    --no_align --compute_type float32
}

log_step "Run 1..."
out1="$RUN_DIR/T2-run1"
t0="$(date +%s)"
if ! capture_normalized T2-run1 run_whisperx "$out1"; then
  log_fail "run 1 failed; see $RUN_DIR/T2-run1.log"
  exit 1
fi
t1="$(date +%s)"
log_pass "run 1 wall: $((t1 - t0)) s"

log_step "Run 2 (warm cache)..."
out2="$RUN_DIR/T2-run2"
t2="$(date +%s)"
if ! capture_normalized T2-run2 run_whisperx "$out2"; then
  log_fail "run 2 failed; see $RUN_DIR/T2-run2.log"
  exit 1
fi
t3="$(date +%s)"
log_pass "run 2 wall: $((t3 - t2)) s"

# Locate the .txt outputs (whisperX names by input basename).
txt1="$(ls "$out1"/*.txt 2>/dev/null | head -1 || true)"
txt2="$(ls "$out2"/*.txt 2>/dev/null | head -1 || true)"

if [ -z "$txt1" ] || [ -z "$txt2" ]; then
  log_fail "missing output txt — txt1=$txt1 txt2=$txt2"
  exit 1
fi

sha1="$(shasum -a 256 "$txt1" | awk '{print $1}')"
sha2="$(shasum -a 256 "$txt2" | awk '{print $1}')"

if [ "$sha1" = "$sha2" ]; then
  log_pass "byte-identical across runs (SHA-256 $sha1)"
  exit 0
fi

log_fail "transcripts diverged"
echo "  run1 SHA-256: $sha1"
echo "  run2 SHA-256: $sha2"
echo "  diff:"
diff -u "$txt1" "$txt2" | sed 's/^/    /' | head -20
exit 1
