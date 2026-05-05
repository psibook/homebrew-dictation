#!/usr/bin/env bash
# tools/two-stage.sh — pipe audio through Whisper, then reason over the
# transcript with Gemma 4 26B-A4B.
#
# Stage 1: whisperX produces a transcript (no diarisation, no alignment)
# Stage 2: Gemma 4 26B-A4B (MoE, mixed-precision MLX-4bit) reasons over the text
#
# Usage:
#   tools/two-stage.sh <audio.wav> "<reasoning prompt>" [--model MODEL]
#
# Example:
#   tools/two-stage.sh demo.wav "Summarize what the speaker is testing"

set -uo pipefail

AUDIO="${1:-}"
TASK="${2:-Summarize the content of this audio.}"
MODEL="${3:-unsloth/gemma-4-26b-a4b-it-UD-MLX-4bit}"

if [ -z "$AUDIO" ] || [ ! -f "$AUDIO" ]; then
  echo "Usage: $0 <audio.wav> \"<reasoning prompt>\" [model]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
base="$(basename "$AUDIO")"
base="${base%.*}"
outdir="outputs/two-stage/${ts}-${base}"
mkdir -p "$outdir"

echo "Stage 1: transcribing $AUDIO via whisperX..." >&2
/Users/dev/.local/bin/whisperx "$AUDIO" \
  --model large-v3 \
  --task transcribe \
  --language en \
  --output_dir "$outdir" \
  --output_format txt \
  --no_align \
  --compute_type float32 \
  > "$outdir/whisperx.log" 2>&1

# Locate transcript output
transcript_file="$(ls "$outdir"/*.txt 2>/dev/null | head -1)"
if [ -z "$transcript_file" ] || [ ! -s "$transcript_file" ]; then
  echo "Stage 1 FAILED: no transcript produced. See $outdir/whisperx.log" >&2
  exit 1
fi
transcript="$(cat "$transcript_file")"

echo "Transcript:" >&2
echo "  $transcript" >&2
echo >&2

echo "Stage 2: reasoning via $MODEL..." >&2

# Build the prompt
prompt="You are reasoning over an audio transcript.

Transcript:
\"$transcript\"

Task: $TASK"

/usr/bin/time -p /Users/dev/.local/bin/mlx_vlm.generate \
  --model "$MODEL" \
  --prompt "$prompt" \
  --max-tokens 500 \
  --temperature 0.7 \
  > "$outdir/gemma.log" 2>&1

# Extract just the model's response (between the second pair of ===)
awk '
  /^==========$/ { state++; next }
  state == 1 && /^Prompt:/ { in_prompt=1; next }
  state == 1 && in_prompt && /^$/ { in_prompt=0; next }
  state == 1 && !in_prompt { print }
' "$outdir/gemma.log" > "$outdir/reasoning.txt"

echo
echo "=== STAGE 1 — TRANSCRIPT ==="
echo "$transcript"
echo
echo "=== STAGE 2 — REASONING ($MODEL) ==="
cat "$outdir/reasoning.txt"
echo
echo "Output dir: $outdir"
