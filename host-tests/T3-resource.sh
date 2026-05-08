#!/usr/bin/env bash
# T3-resource.sh — does whisperX peak under a sane memory budget?
#
# WHY: F30 (gemma-on-vm) measured whisperX peak RSS at 8.43 GiB on the
# source VM (M3 Max paravirtualised). On low-RAM hosts (16 GiB MacBook
# Air, base-model Mac mini) that headroom matters — if whisperX peaks
# closer to system memory, the OS will start swapping and the F29
# byte-stable property may not hold under pressure.
#
# Pass criterion: peak RSS < BUDGET_GIB (default 12 GiB). Override via
# environment: BUDGET_GIB=8 host-tests/T3-resource.sh
#
# Implementation: sample RSS every 0.5 s during the run via a recursive
# pgrep walker. F31 documented the lsof methodology pitfall (`lsof -i
# -p` ORs the selectors); this script avoids that by walking the pgrep
# tree explicitly.

set -uo pipefail
TEST_ID="T3-resource"
BUDGET_GIB="${BUDGET_GIB:-12}"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

WHISPERX="$(locate_whisperx)" || { log_fail "whisperx not found"; exit 1; }
FIXTURE_DIR="$(locate_fixture_dir)" || { log_fail "fixture dir not found"; exit 1; }
INPUT="$FIXTURE_DIR/demo-audio-for-gemma.wav"

# Sampler: print summed RSS (in bytes) of $1 and all descendants every 0.5s.
sample_rss() {
  local root_pid="$1"
  local rss_file="$2"
  local total
  while kill -0 "$root_pid" 2>/dev/null; do
    total=0
    # Recursive descendant walk
    local pids; pids="$(_descendants "$root_pid")"
    for p in $root_pid $pids; do
      local rss
      rss="$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')"
      [ -n "$rss" ] && total=$((total + rss))
    done
    # ps RSS is KB on macOS; convert to bytes.
    echo "$((total * 1024))" >> "$rss_file"
    sleep 0.5
  done
}
_descendants() {
  local parent="$1"
  local children
  children="$(pgrep -P "$parent" 2>/dev/null || true)"
  [ -z "$children" ] && return
  echo "$children"
  for c in $children; do
    _descendants "$c"
  done
}

log_step "Running whisperX with RSS sampler..."
out="$RUN_DIR/T3-output"
mkdir -p "$out"
rss_file="$RUN_DIR/T3-rss.bytes"
> "$rss_file"

raw_log="$RUN_DIR/T3-whisperx.raw.log"
"$WHISPERX" "$INPUT" \
  --model large-v3 --task translate \
  --output_dir "$out" --output_format txt \
  --no_align --compute_type float32 \
  >"$raw_log" 2>&1 &
whisperx_pid=$!

sample_rss "$whisperx_pid" "$rss_file" &
sampler_pid=$!

if ! wait "$whisperx_pid"; then
  kill "$sampler_pid" 2>/dev/null || true
  "$NORMALIZE" <"$raw_log" >"$RUN_DIR/T3-whisperx.log"
  log_fail "whisperx failed; see $RUN_DIR/T3-whisperx.log"
  exit 1
fi
kill "$sampler_pid" 2>/dev/null || true
wait "$sampler_pid" 2>/dev/null || true

"$NORMALIZE" <"$raw_log" >"$RUN_DIR/T3-whisperx.log"

if [ ! -s "$rss_file" ]; then
  log_fail "RSS sampler captured no samples (whisperx finished too quickly?)"
  exit 1
fi

# Compute peak in GiB.
peak_bytes="$(sort -n "$rss_file" | tail -1)"
peak_gib="$(awk -v b="$peak_bytes" 'BEGIN { printf "%.2f", b / 1073741824 }')"
samples="$(wc -l < "$rss_file" | tr -d ' ')"

echo "  samples: $samples"
echo "  peak RSS: $peak_gib GiB (budget: $BUDGET_GIB GiB)"

# Compare numerically.
if awk -v p="$peak_gib" -v b="$BUDGET_GIB" 'BEGIN { exit !(p < b) }'; then
  log_pass "peak RSS $peak_gib GiB < $BUDGET_GIB GiB"
  exit 0
fi
log_fail "peak RSS $peak_gib GiB exceeded budget $BUDGET_GIB GiB"
exit 1
