#!/usr/bin/env bash
# whisper-compare.sh — run an audio file through all installed Whisper backends.
#
# Usage:
#   tools/whisper-compare.sh <input.wav> [translate|transcribe] [language]
#
# Each backend writes to outputs/<timestamp>-<basename>-<task>/<backend>/
# A summary table is printed at the end with wall time and the first 200 chars of output.

set -uo pipefail

INPUT="${1:-}"
TASK="${2:-translate}"
LANG="${3:-}"

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "Usage: $0 <input.wav> [translate|transcribe] [language]" >&2
  echo "  Example: $0 '/Volumes/My Shared Files/receive-from-vm/foo.wav' translate" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
base="$(basename "$INPUT")"
base="${base%.*}"
outdir="outputs/${ts}-${base}-${TASK}"
mkdir -p "$outdir"

echo "Input:  $INPUT"
echo "Task:   $TASK"
[ -n "$LANG" ] && echo "Lang:   $LANG"
echo "Output: $outdir"
echo

run_backend() {
  local name="$1"; shift
  local logf="$outdir/${name}.log"
  local timef="$outdir/${name}.time"
  echo ">>> $name"
  /usr/bin/time -p bash -c "$*" >"$logf" 2>&1
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "  OK"
  else
    echo "  FAIL (exit $rc) — see $logf"
  fi
  return $rc
}

# 1. openai-whisper -----------------------------------------------------------
if [ -x /Users/dev/.local/bin/whisper ]; then
  mkdir -p "$outdir/openai-whisper"
  args=(--model large-v3 --task "$TASK"
        --output_dir "$outdir/openai-whisper"
        --output_format txt --verbose False)
  [ -n "$LANG" ] && args+=(--language "$LANG")
  run_backend openai-whisper \
    "/Users/dev/.local/bin/whisper '$INPUT' ${args[*]}"
else
  echo "openai-whisper: not installed"
fi

# 2. mlx-whisper --------------------------------------------------------------
if [ -x /Users/dev/.local/bin/mlx_whisper ]; then
  mkdir -p "$outdir/mlx-whisper"
  args=(--model mlx-community/whisper-large-v3-mlx
        --task "$TASK"
        --output-dir "$outdir/mlx-whisper"
        --output-format txt)
  [ -n "$LANG" ] && args+=(--language "$LANG")
  run_backend mlx-whisper \
    "/Users/dev/.local/bin/mlx_whisper '$INPUT' ${args[*]}"
else
  echo "mlx-whisper: not installed"
fi

# 3. whisperX -----------------------------------------------------------------
if [ -x /Users/dev/.local/bin/whisperx ]; then
  mkdir -p "$outdir/whisperx"
  args=(--model large-v3 --task "$TASK"
        --output_dir "$outdir/whisperx"
        --output_format txt
        --no_align --compute_type float32)
  [ -n "$LANG" ] && args+=(--language "$LANG")
  run_backend whisperx \
    "/Users/dev/.local/bin/whisperx '$INPUT' ${args[*]}"
else
  echo "whisperx: not installed"
fi

# 4. whisper.cpp --------------------------------------------------------------
if [ -x tools/whisper.cpp/build/bin/whisper-cli ] && \
   [ -f tools/whisper.cpp/models/ggml-large-v3.bin ]; then
  mkdir -p "$outdir/whisper-cpp"
  # whisper.cpp needs 16kHz mono PCM; resample
  ffmpeg -y -i "$INPUT" -ar 16000 -ac 1 -f wav "$outdir/whisper-cpp/input-16k.wav" \
    >"$outdir/whisper-cpp/ffmpeg.log" 2>&1
  flags=""
  [ "$TASK" = "translate" ] && flags="--translate"
  [ -n "$LANG" ] && flags="$flags --language $LANG"
  run_backend whisper-cpp \
    "tools/whisper.cpp/build/bin/whisper-cli \
       -f '$outdir/whisper-cpp/input-16k.wav' \
       -m tools/whisper.cpp/models/ggml-large-v3.bin \
       $flags \
       -of '$outdir/whisper-cpp/output' \
       -otxt"
else
  echo "whisper.cpp: not built (run: cd tools/whisper.cpp && cmake -B build && cmake --build build && bash ./models/download-ggml-model.sh large-v3)"
fi

# 5. insanely-fast-whisper ----------------------------------------------------
# DYLD_LIBRARY_PATH must be set INSIDE bash -c (SIP strips DYLD_* on system
# binaries like /usr/bin/time and /bin/bash). Path quoting is also fragile —
# we explicitly single-quote $INPUT and the JSON path inside the command string.
if [ -x /Users/dev/.local/bin/insanely-fast-whisper ]; then
  mkdir -p "$outdir/insanely-fast-whisper"
  ifw_lang=""
  [ -n "$LANG" ] && ifw_lang="--language '$LANG'"
  run_backend insanely-fast-whisper \
    "export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/opt/ffmpeg@7/lib:\${DYLD_FALLBACK_LIBRARY_PATH:-}; \
     /Users/dev/.local/bin/insanely-fast-whisper \
       --file-name '$INPUT' \
       --model-name openai/whisper-large-v3 \
       --task '$TASK' \
       --device-id mps \
       --transcript-path '$outdir/insanely-fast-whisper/output.json' \
       $ifw_lang"
else
  echo "insanely-fast-whisper: not installed"
fi

# Summary ---------------------------------------------------------------------
echo
echo "=================== SUMMARY ==================="
printf "%-22s | %-10s | %s\n" "BACKEND" "WALL (s)" "FIRST 200 CHARS"
printf "%-22s-+-%-10s-+-%s\n" "----------------------" "----------" "$(printf '%.0s-' {1..60})"
for bk in openai-whisper mlx-whisper whisperx whisper-cpp insanely-fast-whisper; do
  wall="-"
  text="(no output)"
  if [ -f "$outdir/${bk}.log" ]; then
    wall="$(awk '/^real /{print $2}' "$outdir/${bk}.log" | tail -1)"
    [ -z "$wall" ] && wall="?"
  fi
  case "$bk" in
    whisper-cpp)
      [ -f "$outdir/whisper-cpp/output.txt" ] && \
        text="$(head -c 200 "$outdir/whisper-cpp/output.txt")"
      ;;
    insanely-fast-whisper)
      [ -f "$outdir/insanely-fast-whisper/output.json" ] && \
        text="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("text",""))' "$outdir/insanely-fast-whisper/output.json" 2>/dev/null | head -c 200)"
      ;;
    *)
      f="$(ls "$outdir/${bk}"/*.txt 2>/dev/null | head -1)"
      [ -n "$f" ] && text="$(head -c 200 "$f")"
      ;;
  esac
  text="$(echo "$text" | tr '\n' ' ')"
  printf "%-22s | %-10s | %s\n" "$bk" "$wall" "$text"
done
echo
echo "Full outputs: $outdir/"
