#!/usr/bin/env bash
# tests/run-failure-corpus.sh — run every WAV in test-corpus/ through the harness
# and produce a single comparison table.
#
# Usage: tests/run-failure-corpus.sh [translate|transcribe]
# Output: corpus-results/<timestamp>/<file>/* + corpus-results/<timestamp>/SUMMARY.md

set -uo pipefail
TASK="${1:-transcribe}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
batch_dir="corpus-results/${ts}-${TASK}"
mkdir -p "$batch_dir"
summary="$batch_dir/SUMMARY.md"

{
  echo "# Failure-Corpus Comparison Report"
  echo
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')  "
  echo "**Task:** \`$TASK\`  "
  echo "**Backends:** openai-whisper · mlx-whisper · whisperX · whisper.cpp (insanely-fast-whisper omitted, see PLAN.md F5)"
  echo
  echo "| # | Test case | Expected difficulty |"
  echo "|---|---|---|"
  echo "| 01 | Silence (30 s) | Hallucination trigger |"
  echo "| 02 | 8 kHz phone-quality of Simon's clip | Below 16 kHz training distribution |"
  echo "| 03 | Codec round-trip (6 kbps Opus) of Simon's clip | Severe spectral degradation |"
  echo "| 04 | 600 ms clip | Mel-spec context too thin |"
  echo "| 05 | JFK canonical | Clean baseline |"
  echo "| 06 | Music (440 Hz tone) + Simon's speech | Encoder gets distracted by harmonics |"
  echo "| 07 | Simon × Simon offset 2 s (speaker overlap) | No diarisation; conflates |"
  echo "| 08 | Pink noise + Simon (low SNR) | Severe noise robustness |"
  echo "| 09 | Pseudo-whispered Simon | Voiceless phonation lacks pitch cues |"
  echo
  echo "## Results"
  echo
} > "$summary"

for f in test-corpus/*.wav; do
  base="$(basename "$f" .wav)"
  echo ">>> $base"
  ./tools/whisper-compare.sh "$f" "$TASK" en >"$batch_dir/${base}.harness.log" 2>&1
  rc=$?
  # Find latest run output dir produced by the harness
  produced="$(ls -td outputs/*-${base}-${TASK} 2>/dev/null | head -1)"
  if [ -n "$produced" ] && [ -d "$produced" ]; then
    cp -r "$produced" "$batch_dir/${base}/"
  fi

  {
    echo "### $base"
    echo
    echo "| Backend | Wall (s) | Output |"
    echo "|---|---:|---|"
    for bk in openai-whisper mlx-whisper whisperx whisper-cpp; do
      wall="-"
      text="(no output)"
      if [ -f "$batch_dir/${base}/${bk}.log" ]; then
        wall="$(awk '/^real /{print $2}' "$batch_dir/${base}/${bk}.log" | tail -1)"
        [ -z "$wall" ] && wall="?"
      fi
      case "$bk" in
        whisper-cpp)
          [ -f "$batch_dir/${base}/whisper-cpp/output.txt" ] && \
            text="$(cat "$batch_dir/${base}/whisper-cpp/output.txt" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/|/\\|/g')"
          ;;
        *)
          ff="$(ls "$batch_dir/${base}/${bk}"/*.txt 2>/dev/null | head -1)"
          [ -n "$ff" ] && text="$(cat "$ff" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/|/\\|/g')"
          ;;
      esac
      # Trim to 250 chars to keep table readable
      text="${text:0:250}"
      echo "| $bk | $wall | $text |"
    done
    echo
  } >> "$summary"
done

echo
echo "Summary written: $summary"
echo
cat "$summary"
