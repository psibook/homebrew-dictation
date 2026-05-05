#!/usr/bin/env bash
# tools/gemma4-batch.sh — run Gemma 4 E4B (mlx-vlm) over the failure corpus
# and save outputs alongside Whisper results.
#
# Usage: tools/gemma4-batch.sh [E4B|E2B]

set -uo pipefail
VARIANT="${1:-E4B}"
MODEL="google/gemma-4-${VARIANT}-it"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
batch_dir="corpus-results/${ts}-gemma4-${VARIANT}"
mkdir -p "$batch_dir"

echo "Model: $MODEL"
echo "Output: $batch_dir"
echo

for f in test-corpus/*.wav; do
  base="$(basename "$f" .wav)"
  echo ">>> $base"
  outf="$batch_dir/${base}.txt"
  logf="$batch_dir/${base}.log"

  /usr/bin/time -p /Users/dev/.local/bin/mlx_vlm.generate \
    --model "$MODEL" \
    --audio "$f" \
    --prompt "Transcribe this audio." \
    --max-tokens 500 \
    --temperature 1.0 \
    > "$logf" 2>&1
  rc=$?

  # The model output appears between "==========" lines; extract it
  awk '
    /^==========$/ { state++; next }
    state == 1 && /^Prompt:/ { in_prompt=1; next }
    state == 1 && in_prompt && /^$/ { in_prompt=0; next }
    state == 1 && !in_prompt { print }
  ' "$logf" > "$outf"

  if [ $rc -eq 0 ] && [ -s "$outf" ]; then
    echo "  OK ($(wc -c < "$outf") bytes)"
  else
    echo "  FAIL (exit $rc)"
  fi
done

echo
echo "Done. Outputs in: $batch_dir"
