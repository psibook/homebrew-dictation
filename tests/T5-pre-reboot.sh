#!/usr/bin/env bash
# tests/T5-pre-reboot.sh — Phase 3 hardening: capture pre-reboot baseline.
#
# Companion: tests/T5-post-reboot.sh (run after a VM reboot to compare).
#
# Captures a fingerprint of the install state so that a post-reboot run
# can confirm:
#   - All backend binaries still present (paths + sha256)
#   - All model files still present (paths + size + sha256 of model bin)
#   - HF cache snapshot list unchanged
#   - tests/smoke.sh still produces 5/5 PASS
#
# Output: corpus-results/<ts>-T5-pre-reboot/baseline.txt
#         corpus-results/<ts>-T5-pre-reboot/smoke.exit

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
T5DIR="corpus-results/${ts}-T5-pre-reboot"
mkdir -p "$T5DIR"
BASELINE="$T5DIR/baseline.txt"

echo "T5 pre-reboot baseline capture"
echo "Output: $T5DIR"
echo

{
  echo "# T5 Pre-Reboot Baseline"
  echo
  echo "Captured: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Hostname: $(hostname)"
  echo "Uptime:   $(uptime)"
  echo
  echo "## Backend binaries"
  echo
  for bin in \
    /Users/dev/.local/bin/whisper \
    /Users/dev/.local/bin/mlx_whisper \
    /Users/dev/.local/bin/whisperx \
    /Users/dev/.local/bin/insanely-fast-whisper \
    /Users/dev/.local/bin/mlx_vlm.generate \
    "tools/whisper.cpp/build/bin/whisper-cli"; do
    if [ -x "$bin" ]; then
      sha="$(shasum -a 256 "$bin" | awk '{print $1}')"
      sz="$(stat -f %z "$bin")"
      echo "  OK    $bin  size=$sz  sha256=${sha:0:16}..."
    else
      echo "  MISS  $bin"
    fi
  done
  echo
  echo "## Model files"
  echo
  if [ -f tools/whisper.cpp/models/ggml-large-v3.bin ]; then
    bin=tools/whisper.cpp/models/ggml-large-v3.bin
    sha="$(shasum -a 256 "$bin" | awk '{print $1}')"
    sz="$(stat -f %z "$bin")"
    echo "  OK    $bin  size=$sz  sha256=${sha:0:16}..."
  else
    echo "  MISS  tools/whisper.cpp/models/ggml-large-v3.bin"
  fi
  echo
  echo "## HuggingFace cache snapshots"
  echo
  for d in ~/.cache/huggingface/hub/models--*; do
    [ -d "$d" ] || continue
    bn="$(basename "$d")"
    refs="$d/refs/main"
    if [ -f "$refs" ]; then
      echo "  $bn  ref=$(cat "$refs")"
    else
      echo "  $bn  (no refs/main)"
    fi
  done
  echo
  echo "## tests/smoke.sh outcome"
  echo
} > "$BASELINE"

# Run the existing smoke test, capture its exit code
echo ">>> running tests/smoke.sh ..."
tests/smoke.sh > "$T5DIR/smoke.log" 2>&1
smoke_rc=$?
echo "$smoke_rc" > "$T5DIR/smoke.exit"
{
  echo "  exit: $smoke_rc"
  echo "  log: $T5DIR/smoke.log"
  echo
  if [ "$smoke_rc" -eq 0 ]; then
    echo "  Verdict: smoke 5/5 PASS — baseline is healthy."
  else
    echo "  Verdict: smoke FAILED — baseline is NOT healthy. Fix before reboot."
  fi
} >> "$BASELINE"

echo
echo "Baseline written: $BASELINE"
echo
echo "===== Next step (after Lieutenant reboots the VM) ====="
echo "  tests/T5-post-reboot.sh $T5DIR"
echo
echo "Baseline summary:"
echo
cat "$BASELINE"

exit "$smoke_rc"
