#!/usr/bin/env bash
# tests/T3-resource.sh — Phase 3 hardening: resource-bound test.
#
# Goal: measure peak resident memory (RSS) for each backend during
# inference on the demo file. Verify each fits within its documented
# memory budget on this 64 GiB VM.
#
# Method:
#   1. Launch backend in background, capture PID.
#   2. Sampler polls the backend's process tree every 0.5 s, sums RSS
#      across all descendants.
#   3. Record peak RSS, report in MiB.
#
# Output: corpus-results/<ts>-T3-resource/SUMMARY.md
#
# Usage: tests/T3-resource.sh [demo.wav]

set -uo pipefail

DEMO="${1:-/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav}"
[ ! -f "$DEMO" ] && { echo "FAIL: demo file not found: $DEMO" >&2; exit 2; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
T3DIR="corpus-results/${ts}-T3-resource"
mkdir -p "$T3DIR"

echo "T3 resource-bound harness"
echo "Input:  $DEMO"
echo "Output: $T3DIR"
echo

# ------------------------------------------------------------------
# Recursive PID walker (descendants of $1, including itself).
# ------------------------------------------------------------------
descendants() {
  local pid="$1"
  echo "$pid"
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    descendants "$child"
  done
}

# Sum RSS (KiB) across a list of PIDs. Missing PIDs contribute 0.
sum_rss_kb() {
  local total=0
  for pid in "$@"; do
    local r
    r="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$r" ] && total=$((total + r))
  done
  echo "$total"
}

# Sample peak RSS while $1 (a PID) is alive. Polls every 0.5 s.
# Writes CSV to $2: ts_iso,total_kb,peak_kb
sample_peak() {
  local pid="$1"
  local csv="$2"
  local peak=0
  echo "ts_iso,total_kb,peak_kb" > "$csv"
  while kill -0 "$pid" 2>/dev/null; do
    local pids; pids=($(descendants "$pid"))
    local total; total=$(sum_rss_kb "${pids[@]}")
    [ "$total" -gt "$peak" ] && peak="$total"
    printf '%s,%s,%s\n' "$(date '+%H:%M:%S')" "$total" "$peak" >> "$csv"
    sleep 0.5
  done
  echo "$peak"
}

# ------------------------------------------------------------------
# Per-backend run-and-measure
# ------------------------------------------------------------------

measure_one() {
  local name="$1"; shift
  local outdir="$T3DIR/$name"
  mkdir -p "$outdir"
  echo ">>> $name"

  # Launch backend in background
  bash -c "$*" >"$outdir/run.log" 2>&1 &
  local bk_pid=$!

  # Sample RSS until the backend exits
  local peak_kb
  peak_kb="$(sample_peak "$bk_pid" "$outdir/sample.csv")"

  wait "$bk_pid"
  local rc=$?

  local peak_mib=$((peak_kb / 1024))
  printf "    rc=%d  peak=%d MiB (%d KiB)\n" "$rc" "$peak_mib" "$peak_kb"
  echo "$peak_kb" > "$outdir/peak_kb"
  echo "$rc"     > "$outdir/rc"
}

# ------------------------------------------------------------------
# Backends — same invocations as T2-repeat.sh
# ------------------------------------------------------------------

measure_one "openai-whisper" \
  "/Users/dev/.local/bin/whisper '$DEMO' \
     --model large-v3 --task translate \
     --output_dir '$T3DIR/openai-whisper' --output_format txt --verbose False"

measure_one "mlx-whisper" \
  "/Users/dev/.local/bin/mlx_whisper '$DEMO' \
     --model mlx-community/whisper-large-v3-mlx --task translate \
     --output-dir '$T3DIR/mlx-whisper' --output-format txt"

measure_one "whisperx" \
  "/Users/dev/.local/bin/whisperx '$DEMO' \
     --model large-v3 --task translate \
     --output_dir '$T3DIR/whisperx' --output_format txt \
     --no_align --compute_type float32"

# whisper.cpp needs 16kHz mono WAV; resample once
ffmpeg -y -i "$DEMO" -ar 16000 -ac 1 -f wav "$T3DIR/input-16k.wav" \
  >"$T3DIR/ffmpeg.log" 2>&1
measure_one "whisper-cpp" \
  "tools/whisper.cpp/build/bin/whisper-cli \
     -f '$T3DIR/input-16k.wav' \
     -m tools/whisper.cpp/models/ggml-large-v3.bin \
     --translate -of '$T3DIR/whisper-cpp/output' -otxt"

measure_one "ifw" \
  "export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/opt/ffmpeg@7/lib; \
   /Users/dev/.local/bin/insanely-fast-whisper \
     --file-name '$DEMO' \
     --model-name openai/whisper-large-v3 \
     --task translate --device-id mps \
     --transcript-path '$T3DIR/ifw/output.json'"

measure_one "gemma-e4b" \
  "/Users/dev/.local/bin/mlx_vlm.generate \
     --model google/gemma-4-E4B-it \
     --audio '$DEMO' \
     --prompt 'Transcribe this audio.' \
     --max-tokens 500 --temperature 0.0"

# Also measure Gemma 4 26B-A4B (text-only, used in two-stage)
measure_one "gemma-26b-a4b" \
  "/Users/dev/.local/bin/mlx_vlm.generate \
     --model unsloth/gemma-4-26b-a4b-it-UD-MLX-4bit \
     --prompt 'Summarize: a podcast about reinforcement learning.' \
     --max-tokens 200 --temperature 0.0"

# ------------------------------------------------------------------
# Report
# ------------------------------------------------------------------

REPORT="$T3DIR/SUMMARY.md"
{
  echo "# T3 Resource-Bound Report"
  echo
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Input:** \`$DEMO\` (14 s, 1.3 MiB)"
  echo "**Method:** sample \`ps -o rss=\` over the backend's process tree every 0.5 s; report peak."
  echo "**VM budget:** 64 GiB total RAM."
  echo
  echo "| Backend | Peak RSS (MiB) | Peak RSS (GiB) | rc | % of 64 GiB |"
  echo "|---|---:|---:|---:|---:|"
} > "$REPORT"

echo
echo "==================== T3 RESULTS ===================="
printf "%-15s | %10s | %8s | %3s | %8s\n" "BACKEND" "PEAK (MiB)" "PEAK GiB" "rc" "%/64GiB"
echo "----------------+------------+----------+-----+---------"

for bk in openai-whisper mlx-whisper whisperx whisper-cpp ifw gemma-e4b gemma-26b-a4b; do
  pk_kb=0
  rc="?"
  [ -f "$T3DIR/$bk/peak_kb" ] && pk_kb="$(cat "$T3DIR/$bk/peak_kb")"
  [ -f "$T3DIR/$bk/rc" ]      && rc="$(cat "$T3DIR/$bk/rc")"
  pk_mib=$((pk_kb / 1024))
  pk_gib=$(awk -v k="$pk_kb" 'BEGIN{printf "%.2f", k / 1024 / 1024}')
  pct=$(awk -v k="$pk_kb" 'BEGIN{printf "%.1f", k * 100 / (64 * 1024 * 1024)}')
  printf "%-15s | %10d | %8s | %3s | %7s%%\n" "$bk" "$pk_mib" "$pk_gib" "$rc" "$pct"
  printf "| %s | %d | %s | %s | %s%% |\n" "$bk" "$pk_mib" "$pk_gib" "$rc" "$pct" >> "$REPORT"
done

echo
echo "Report: $REPORT"
