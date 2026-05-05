#!/usr/bin/env bash
# tests/smoke.sh — minimal end-to-end test on the bundled demo file.
#
# Pass criteria:
#   - 4/5 backends produce non-empty translation output
#   - insanely-fast-whisper expected to fail (Finding F5)
#
# Exits 0 if 4/5 pass, 1 otherwise.

set -uo pipefail

DEMO="/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav"
if [ ! -f "$DEMO" ]; then
  echo "FAIL: demo file not present at $DEMO" >&2
  echo "  (Place the WAV in the receive-from-vm courier and retry.)" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo ">>> Running comparison harness..."
./tools/whisper-compare.sh "$DEMO" translate

# Locate the latest output dir
latest="$(ls -td outputs/*-demo-audio-for-gemma-translate 2>/dev/null | head -1)"
if [ -z "$latest" ]; then
  echo "FAIL: no output dir produced" >&2
  exit 1
fi

echo
echo ">>> Pass/fail per backend (latest run: $latest)"
pass=0
fail=0
for bk in openai-whisper mlx-whisper whisperx whisper-cpp insanely-fast-whisper; do
  text=""
  case "$bk" in
    whisper-cpp)
      [ -s "$latest/whisper-cpp/output.txt" ] && text="$(cat "$latest/whisper-cpp/output.txt")"
      ;;
    insanely-fast-whisper)
      [ -s "$latest/insanely-fast-whisper/output.json" ] && \
        text="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("text",""))' "$latest/insanely-fast-whisper/output.json" 2>/dev/null)"
      ;;
    *)
      f="$(ls "$latest/${bk}"/*.txt 2>/dev/null | head -1)"
      [ -n "$f" ] && [ -s "$f" ] && text="$(cat "$f")"
      ;;
  esac
  if [ -n "$text" ] && echo "$text" | grep -qi "voice memo"; then
    echo "  PASS  $bk"
    pass=$((pass+1))
  else
    echo "  FAIL  $bk"
    fail=$((fail+1))
  fi
done

echo
echo "  Summary: $pass pass, $fail fail (target: 4 pass)"

# 4/5 pass = exit 0; below 4 = exit 1
[ "$pass" -ge 4 ] && exit 0 || exit 1
