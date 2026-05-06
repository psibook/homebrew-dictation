#!/usr/bin/env bash
# tests/T5-post-reboot.sh — Phase 3 hardening: verify post-reboot survival.
#
# Companion: tests/T5-pre-reboot.sh (must be run before reboot).
#
# Usage: tests/T5-post-reboot.sh <pre-reboot-dir>
#   e.g. tests/T5-post-reboot.sh corpus-results/2026-05-06-...-T5-pre-reboot
#
# Steps:
#   1. Confirm uptime indicates a recent reboot.
#   2. Re-capture the inventory (binaries, models, HF cache).
#   3. Diff against the pre-reboot baseline.
#   4. Re-run tests/smoke.sh — expect same exit code.
#   5. Report PASS / FAIL.

set -uo pipefail

PRE="${1:-}"
if [ -z "$PRE" ] || [ ! -f "$PRE/baseline.txt" ]; then
  echo "Usage: $0 <pre-reboot-dir>" >&2
  echo "  Latest pre-reboot dir:" >&2
  ls -td corpus-results/*-T5-pre-reboot 2>/dev/null | head -1 | sed 's/^/  /' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
T5DIR="corpus-results/${ts}-T5-post-reboot"
mkdir -p "$T5DIR"
NOW="$T5DIR/post-reboot.txt"

echo "T5 post-reboot verification"
echo "Pre:    $PRE/baseline.txt"
echo "Post:   $T5DIR"
echo

# --- 1. Uptime sanity check -----------------------------------------------
{
  echo "# T5 Post-Reboot Verification"
  echo
  echo "Captured: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Hostname: $(hostname)"
  echo "Uptime:   $(uptime)"
  echo
  echo "## Pre-reboot uptime (for comparison)"
  echo
  grep '^Uptime:' "$PRE/baseline.txt" || echo "  (unknown)"
  echo
} > "$NOW"

# --- 2. Re-capture inventory ----------------------------------------------
{
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
} >> "$NOW"

# --- 3. Diff against pre-reboot baseline ----------------------------------
# Strip volatile fields (dates, uptime line) before diffing.
strip_volatile() {
  sed -e 's/^Captured:.*$/Captured: -/' \
      -e 's/^Uptime:.*$/Uptime: -/' \
      -e '/^## tests\/smoke.sh outcome/,$d' "$1"
}

DIFF="$T5DIR/baseline.diff"
diff <(strip_volatile "$PRE/baseline.txt") <(strip_volatile "$NOW") > "$DIFF" || true

if [ -s "$DIFF" ]; then
  echo "  Inventory diff: NON-EMPTY (see $DIFF)"
  echo
  echo "## Inventory diff vs pre-reboot baseline" >> "$NOW"
  echo >> "$NOW"
  echo '```' >> "$NOW"
  cat "$DIFF" >> "$NOW"
  echo '```' >> "$NOW"
  inventory_status="DIFF"
else
  echo "  Inventory diff: EMPTY (binaries + models + HF cache identical)"
  inventory_status="MATCH"
fi
echo
{
  echo
  echo "**Inventory status:** $inventory_status"
  echo
} >> "$NOW"

# --- 4. Re-run smoke ------------------------------------------------------
echo ">>> running tests/smoke.sh post-reboot ..."
tests/smoke.sh > "$T5DIR/smoke.log" 2>&1
post_smoke_rc=$?
pre_smoke_rc="$(cat "$PRE/smoke.exit" 2>/dev/null || echo "?")"

{
  echo "## Smoke comparison"
  echo
  echo "- Pre-reboot smoke exit:  $pre_smoke_rc"
  echo "- Post-reboot smoke exit: $post_smoke_rc"
  echo
  if [ "$pre_smoke_rc" = "$post_smoke_rc" ]; then
    echo "**Smoke status:** MATCH"
  else
    echo "**Smoke status:** DIVERGE"
  fi
  echo
} >> "$NOW"

# --- 5. Final verdict -----------------------------------------------------
if [ "$inventory_status" = "MATCH" ] && [ "$pre_smoke_rc" = "0" ] && [ "$post_smoke_rc" = "0" ]; then
  verdict="PASS"
elif [ "$inventory_status" = "MATCH" ] && [ "$pre_smoke_rc" = "$post_smoke_rc" ]; then
  verdict="PASS (matched pre-reboot state, but smoke was non-zero)"
else
  verdict="FAIL"
fi

{
  echo "## Final verdict"
  echo
  echo "**T5 Reboot Survival: $verdict**"
} >> "$NOW"

echo
echo "Verdict: $verdict"
echo "Report: $NOW"
[ "$verdict" = "PASS" ] && exit 0 || exit 1
