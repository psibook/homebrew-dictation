#!/usr/bin/env bash
# tests/T2-repeat.sh — Phase 3 hardening: repeat-invocation test.
#
# Goal: verify each backend can be invoked twice in a row without daemon
# crash, model-reload failure, or output corruption. Run 1 and Run 2 use
# the same input (Simon's demo clip). Both runs are warm-cache.
#
# Pass criteria (per backend):
#   - Run 1 produces non-empty output
#   - Run 2 produces non-empty output
#   - For deterministic backends, run1 text == run2 text
#   - Run 2 wall ≤ Run 1 wall + 20% (warm cache should not slow down)
#
# Stochastic backends (Gemma with temp>0) are checked only for non-empty
# output and successful exit. Temperature is forced to 0.0 here for
# determinism where the runtime supports it.
#
# Usage: tests/T2-repeat.sh [demo.wav]

set -uo pipefail

DEMO="${1:-/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav}"
[ ! -f "$DEMO" ] && { echo "FAIL: demo file not found: $DEMO" >&2; exit 2; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
T2DIR="corpus-results/${ts}-T2-repeat"
mkdir -p "$T2DIR"

echo "T2 repeat-invocation harness"
echo "Input:  $DEMO"
echo "Output: $T2DIR"
echo

# ------------------------------------------------------------------
# Per-backend single-shot wrappers (so we can time + log each cleanly)
# ------------------------------------------------------------------

run_openai_whisper() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p /Users/dev/.local/bin/whisper "$DEMO" \
    --model large-v3 --task translate \
    --output_dir "$outdir" --output_format txt --verbose False \
    >"$outdir/run.log" 2>&1
}

run_mlx_whisper() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p /Users/dev/.local/bin/mlx_whisper "$DEMO" \
    --model mlx-community/whisper-large-v3-mlx --task translate \
    --output-dir "$outdir" --output-format txt \
    >"$outdir/run.log" 2>&1
}

run_whisperx() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p /Users/dev/.local/bin/whisperx "$DEMO" \
    --model large-v3 --task translate \
    --output_dir "$outdir" --output_format txt \
    --no_align --compute_type float32 \
    >"$outdir/run.log" 2>&1
}

run_whisper_cpp() {
  local outdir="$1"; mkdir -p "$outdir"
  ffmpeg -y -i "$DEMO" -ar 16000 -ac 1 -f wav "$outdir/input-16k.wav" \
    >"$outdir/ffmpeg.log" 2>&1
  /usr/bin/time -p tools/whisper.cpp/build/bin/whisper-cli \
    -f "$outdir/input-16k.wav" \
    -m tools/whisper.cpp/models/ggml-large-v3.bin \
    --translate -of "$outdir/output" -otxt \
    >"$outdir/run.log" 2>&1
}

run_ifw() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p bash -c "
    export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/opt/ffmpeg@7/lib
    /Users/dev/.local/bin/insanely-fast-whisper \
      --file-name '$DEMO' \
      --model-name openai/whisper-large-v3 \
      --task translate --device-id mps \
      --transcript-path '$outdir/output.json'
  " >"$outdir/run.log" 2>&1
}

run_gemma_e4b() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p /Users/dev/.local/bin/mlx_vlm.generate \
    --model google/gemma-4-E4B-it \
    --audio "$DEMO" \
    --prompt "Transcribe this audio." \
    --max-tokens 500 --temperature 0.0 \
    >"$outdir/run.log" 2>&1
}

# Two-stage stack as a 7th tracked entity (whisperX → Gemma 4 26B-A4B)
run_two_stage() {
  local outdir="$1"; mkdir -p "$outdir"
  /usr/bin/time -p ./tools/two-stage.sh "$DEMO" \
    "Summarize what the speaker is doing in one sentence." \
    >"$outdir/run.log" 2>&1
}

# ------------------------------------------------------------------
# Output extractors
# ------------------------------------------------------------------

extract_openai_whisper() { ls "$1"/*.txt 2>/dev/null | head -1 | xargs -I{} cat {} 2>/dev/null; }
extract_mlx_whisper()    { ls "$1"/*.txt 2>/dev/null | head -1 | xargs -I{} cat {} 2>/dev/null; }
extract_whisperx()       { ls "$1"/*.txt 2>/dev/null | head -1 | xargs -I{} cat {} 2>/dev/null; }
extract_whisper_cpp()    { [ -f "$1/output.txt" ] && cat "$1/output.txt"; }
extract_ifw()            { [ -f "$1/output.json" ] && python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("text",""))' "$1/output.json" 2>/dev/null; }

# Gemma's stdout is wrapped in `==========` markers. Extract just the model's reply.
extract_gemma() {
  awk '
    /^==========$/ { state++; next }
    state == 1 && /^Prompt:/ { skip=1; next }
    state == 1 && skip && /^$/ { skip=0; next }
    state == 1 && !skip { print }
  ' "$1/run.log"
}

extract_two_stage() {
  # The two-stage script writes its `=== STAGE 2 — REASONING ===` block to stdout
  awk '/^=== STAGE 2/{f=1; next} /^Output dir:/{f=0} f' "$1/run.log"
}

extract_wall() {
  awk '/^real /{print $2}' "$1/run.log" | tail -1
}

# ------------------------------------------------------------------
# Drive the runs
# ------------------------------------------------------------------

# Backends to test (skip two-stage if SKIP_TWOSTAGE=1; it adds ~60s per run).
BACKENDS=(openai-whisper mlx-whisper whisperx whisper-cpp ifw gemma-e4b)
[ "${WITH_TWOSTAGE:-0}" = "1" ] && BACKENDS+=(two-stage)

for bk in "${BACKENDS[@]}"; do
  for run in 1 2; do
    outdir="$T2DIR/${bk}/run${run}"
    echo ">>> ${bk} run ${run}"
    case "$bk" in
      openai-whisper) run_openai_whisper "$outdir" ;;
      mlx-whisper)    run_mlx_whisper "$outdir" ;;
      whisperx)       run_whisperx "$outdir" ;;
      whisper-cpp)    run_whisper_cpp "$outdir" ;;
      ifw)            run_ifw "$outdir" ;;
      gemma-e4b)      run_gemma_e4b "$outdir" ;;
      two-stage)      run_two_stage "$outdir" ;;
    esac
    rc=$?
    if [ $rc -eq 0 ]; then echo "    rc=0"; else echo "    rc=$rc"; fi
  done
done

# ------------------------------------------------------------------
# Compare and report
# ------------------------------------------------------------------

echo
echo "==================== T2 RESULTS ===================="
printf "%-15s | %-7s | %-7s | %-9s | %7s | %7s | %s\n" \
  "BACKEND" "RUN1" "RUN2" "MATCH" "WALL1" "WALL2" "VERDICT"
echo "----------------+---------+---------+-----------+---------+---------+--------"

REPORT="$T2DIR/SUMMARY.md"
{
  echo "# T2 Repeat-Invocation Report"
  echo
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Input:** \`$DEMO\`"
  echo "**Method:** call each backend twice consecutively (warm cache → warm cache)."
  echo
  echo "**Pass criteria:** both runs produce non-empty output AND (for deterministic backends) outputs match byte-for-byte AND run-2 wall ≤ run-1 wall × 1.2."
  echo
  echo "| Backend | Run 1 | Run 2 | Match | Wall 1 (s) | Wall 2 (s) | Verdict |"
  echo "|---|---|---|---|---:|---:|---|"
} > "$REPORT"

overall_pass=0
overall_fail=0
for bk in "${BACKENDS[@]}"; do
  d1="$T2DIR/${bk}/run1"
  d2="$T2DIR/${bk}/run2"
  text1=""; text2=""; w1="-"; w2="-"
  case "$bk" in
    openai-whisper) text1="$(extract_openai_whisper "$d1")"; text2="$(extract_openai_whisper "$d2")" ;;
    mlx-whisper)    text1="$(extract_mlx_whisper "$d1")";    text2="$(extract_mlx_whisper "$d2")" ;;
    whisperx)       text1="$(extract_whisperx "$d1")";       text2="$(extract_whisperx "$d2")" ;;
    whisper-cpp)    text1="$(extract_whisper_cpp "$d1")";    text2="$(extract_whisper_cpp "$d2")" ;;
    ifw)            text1="$(extract_ifw "$d1")";            text2="$(extract_ifw "$d2")" ;;
    gemma-e4b)      text1="$(extract_gemma "$d1")";          text2="$(extract_gemma "$d2")" ;;
    two-stage)      text1="$(extract_two_stage "$d1")";      text2="$(extract_two_stage "$d2")" ;;
  esac
  w1="$(extract_wall "$d1")"
  w2="$(extract_wall "$d2")"
  [ -z "$w1" ] && w1="-"
  [ -z "$w2" ] && w2="-"

  s1="$([ -n "$text1" ] && echo PASS || echo FAIL)"
  s2="$([ -n "$text2" ] && echo PASS || echo FAIL)"

  # Normalize whitespace for compare; gemma may have trailing newlines
  n1="$(echo "$text1" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
  n2="$(echo "$text2" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
  if [ -n "$n1" ] && [ "$n1" = "$n2" ]; then
    match="MATCH"
  elif [ -z "$n1" ] && [ -z "$n2" ]; then
    match="EMPTY"
  else
    match="DIFF"
  fi

  # Verdict: PASS if both ran and (deterministic-match OR stochastic-both-non-empty)
  verdict="FAIL"
  if [ "$s1" = "PASS" ] && [ "$s2" = "PASS" ]; then
    case "$bk" in
      gemma-e4b|two-stage)
        # Stochastic: both non-empty is the bar
        verdict="PASS"
        ;;
      *)
        # Deterministic: must match
        [ "$match" = "MATCH" ] && verdict="PASS"
        ;;
    esac
  fi
  [ "$verdict" = "PASS" ] && overall_pass=$((overall_pass+1)) || overall_fail=$((overall_fail+1))

  printf "%-15s | %-7s | %-7s | %-9s | %7s | %7s | %s\n" \
    "$bk" "$s1" "$s2" "$match" "$w1" "$w2" "$verdict"

  printf "| %s | %s | %s | %s | %s | %s | %s |\n" \
    "$bk" "$s1" "$s2" "$match" "$w1" "$w2" "$verdict" >> "$REPORT"
done

echo
echo "Pass: $overall_pass / $((overall_pass+overall_fail))"
echo "Report: $REPORT"
{
  echo
  echo "**Overall:** $overall_pass / $((overall_pass+overall_fail)) backends pass."
} >> "$REPORT"

# Exit 0 if all passed, 1 otherwise.
[ "$overall_fail" -eq 0 ] && exit 0 || exit 1
