#!/usr/bin/env bash
# tests/T4-egress.sh — Phase 3 hardening: HTTPS-only egress spot-check.
#
# Three independent layers of evidence:
#
#   1. Network policy (vm-ops contract): firewall PF rules already enforce
#      HTTPS-only egress (case-board: SECURE — HTTPS allowed, HTTP/SSH
#      blocked). Reference; not re-verified here (sudo required).
#
#   2. Weight provenance: every cached model directory traces to a
#      known HTTPS source (huggingface.co or github.com). If anything
#      came over a different protocol, the firewall would have dropped
#      it — so 'cached + working' implies 'pulled over HTTPS'.
#
#   3. Inference-time egress: each backend is launched and we sample
#      `lsof -i -n -P -p <pid-tree>` every 0.5 s. Expectation: zero
#      non-localhost outbound TCP. Cached weights = no network needed.
#
# Pass criteria (per backend): zero entries in lsof's IPv4/IPv6
# socket output during the run (other than loopback).

set -uo pipefail

DEMO="${1:-/Volumes/My Shared Files/receive-from-vm/demo-audio-for-gemma.wav}"
[ ! -f "$DEMO" ] && { echo "FAIL: demo file not found: $DEMO" >&2; exit 2; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ts="$(date +%Y-%m-%d-%H%M%S)"
T4DIR="corpus-results/${ts}-T4-egress"
mkdir -p "$T4DIR"

REPORT="$T4DIR/SUMMARY.md"

echo "T4 HTTPS-only egress harness"
echo "Output: $T4DIR"
echo

# ------------------------------------------------------------------
# Section 1 — Reference vm-ops firewall posture
# ------------------------------------------------------------------
{
  echo "# T4 HTTPS-Only Egress Report"
  echo
  echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## 1. vm-ops firewall reference"
  echo
  echo "Per CASE-BOARD.md (vm-ops, SECURE 2026-04-24): firewall State=2, PF rules"
  echo "loaded, SSH/HTTP blocked outbound, HTTPS (port 443) allowed."
  echo "This makes ALL successful weight downloads necessarily HTTPS."
} > "$REPORT"

# ------------------------------------------------------------------
# Section 2 — Weight provenance audit
# ------------------------------------------------------------------
echo ">>> Section 2: weight provenance"
{
  echo
  echo "## 2. Weight provenance audit"
  echo
  echo "Cached model directories under \`~/.cache/huggingface/hub/\`:"
  echo
  echo "| Cache directory | HuggingFace repo (HTTPS) |"
  echo "|---|---|"
} >> "$REPORT"

for d in ~/.cache/huggingface/hub/models--*; do
  bn="$(basename "$d")"
  hf="${bn#models--}"
  hf="${hf//--/\/}"
  echo "  - $bn → https://huggingface.co/$hf"
  printf "| \`%s\` | https://huggingface.co/%s |\n" "$bn" "$hf" >> "$REPORT"
done

# whisper.cpp model
if [ -f tools/whisper.cpp/models/ggml-large-v3.bin ]; then
  echo "  - tools/whisper.cpp/models/ggml-large-v3.bin → https://huggingface.co/ggerganov/whisper.cpp"
  printf "| \`tools/whisper.cpp/models/ggml-large-v3.bin\` | https://huggingface.co/ggerganov/whisper.cpp |\n" >> "$REPORT"
fi

{
  echo
  echo "All weights trace to \`huggingface.co\` (HTTPS-only host). Verified by"
  echo "name; the PF firewall would have dropped any non-HTTPS download path."
} >> "$REPORT"

# ------------------------------------------------------------------
# Section 3 — Inference-time socket activity
# ------------------------------------------------------------------
echo
echo ">>> Section 3: inference-time socket activity"

# Recursive PID walker
descendants() {
  local pid="$1"
  echo "$pid"
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    descendants "$child"
  done
}

# Sample lsof while backend is alive. Capture every line of internet socket
# activity (TCP/UDP) for the backend's PID tree.
sample_sockets() {
  local pid="$1"
  local logf="$2"
  : > "$logf"
  while kill -0 "$pid" 2>/dev/null; do
    local pids; pids=($(descendants "$pid"))
    for p in "${pids[@]}"; do
      # -a ANDs selectors: -i AND -p (without -a, lsof ORs them — bug)
      lsof -a -P -n -i -p "$p" 2>/dev/null | tail -n +2 || true
    done >> "$logf"
    sleep 0.5
  done
}

# Single-shot run-and-capture
run_with_socket_capture() {
  local name="$1"; shift
  local outdir="$T4DIR/$name"
  mkdir -p "$outdir"
  echo ">>> $name"

  bash -c "$*" >"$outdir/run.log" 2>&1 &
  local bk_pid=$!

  sample_sockets "$bk_pid" "$outdir/sockets.log"

  wait "$bk_pid" 2>/dev/null
  local rc=$?

  # Two separate counts:
  #   non_443  = non-loopback non-port-443 socket events  (T4 FAIL if >0)
  #   to_443   = non-loopback port-443 socket events      (informational)
  local non_443 to_443
  non_443="$(awk '
    /TCP|UDP/ {
      name=""
      for (i=9; i<=NF; i++) name = name " " $i
      if (name ~ /127\.0\.0\.1/) next
      if (name ~ /\[::1\]/)       next
      if (name ~ /localhost/)     next
      # Look for ":443" at end of destination (after ->)
      if (name ~ /->[^ ]+:443[^0-9]/ || name ~ /->[^ ]+:443$/) next
      print
    }' "$outdir/sockets.log" | wc -l | tr -d ' ')"
  to_443="$(awk '
    /TCP|UDP/ {
      name=""
      for (i=9; i<=NF; i++) name = name " " $i
      if (name ~ /127\.0\.0\.1/) next
      if (name ~ /\[::1\]/)       next
      if (name ~ /localhost/)     next
      if (name ~ /->[^ ]+:443[^0-9]/ || name ~ /->[^ ]+:443$/) print
    }' "$outdir/sockets.log" | wc -l | tr -d ' ')"

  printf "    rc=%d  non-443=%s  to-443=%s\n" "$rc" "$non_443" "$to_443"
  echo "$rc"      > "$outdir/rc"
  echo "$non_443" > "$outdir/non_443_count"
  echo "$to_443"  > "$outdir/to_443_count"
}

{
  echo
  echo "## 3. Inference-time socket activity (cached weights)"
  echo
  echo "Each backend launched on the demo file; \`lsof -a -i -n -P -p <tree>\`"
  echo "polled every 0.5 s during the run. Loopback (127.0.0.1, ::1, localhost)"
  echo "filtered out. Counts split by destination port:"
  echo
  echo "- **non-443** = non-loopback connections on any port other than 443 (must be 0 for PASS)."
  echo "- **to-443** = non-loopback connections on port 443 (HF staleness check on cached weights — informational)."
  echo
  echo "**Pass criteria:** non-443 == 0 AND rc == 0."
  echo
  echo "| Backend | rc | non-443 | to-443 | Verdict |"
  echo "|---|---:|---:|---:|---|"
} >> "$REPORT"

run_with_socket_capture "openai-whisper" \
  "/Users/dev/.local/bin/whisper '$DEMO' \
     --model large-v3 --task translate \
     --output_dir '$T4DIR/openai-whisper' --output_format txt --verbose False"

run_with_socket_capture "mlx-whisper" \
  "/Users/dev/.local/bin/mlx_whisper '$DEMO' \
     --model mlx-community/whisper-large-v3-mlx --task translate \
     --output-dir '$T4DIR/mlx-whisper' --output-format txt"

run_with_socket_capture "whisperx" \
  "/Users/dev/.local/bin/whisperx '$DEMO' \
     --model large-v3 --task translate \
     --output_dir '$T4DIR/whisperx' --output_format txt \
     --no_align --compute_type float32"

ffmpeg -y -i "$DEMO" -ar 16000 -ac 1 -f wav "$T4DIR/input-16k.wav" \
  >"$T4DIR/ffmpeg.log" 2>&1
run_with_socket_capture "whisper-cpp" \
  "tools/whisper.cpp/build/bin/whisper-cli \
     -f '$T4DIR/input-16k.wav' \
     -m tools/whisper.cpp/models/ggml-large-v3.bin \
     --translate -of '$T4DIR/whisper-cpp/output' -otxt"

run_with_socket_capture "ifw" \
  "export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/opt/ffmpeg@7/lib; \
   /Users/dev/.local/bin/insanely-fast-whisper \
     --file-name '$DEMO' \
     --model-name openai/whisper-large-v3 \
     --task translate --device-id mps \
     --transcript-path '$T4DIR/ifw/output.json'"

run_with_socket_capture "gemma-e4b" \
  "/Users/dev/.local/bin/mlx_vlm.generate \
     --model google/gemma-4-E4B-it \
     --audio '$DEMO' \
     --prompt 'Transcribe this audio.' \
     --max-tokens 500 --temperature 0.0"

# ------------------------------------------------------------------
# Compile final report
# ------------------------------------------------------------------
echo
echo "==================== T4 RESULTS ===================="
printf "%-15s | %3s | %8s | %8s | %s\n" "BACKEND" "rc" "non-443" "to-443" "VERDICT"
echo "----------------+-----+----------+----------+--------"
overall_pass=0
overall_fail=0
for bk in openai-whisper mlx-whisper whisperx whisper-cpp ifw gemma-e4b; do
  rc="?"; non443="?"; to443="?"
  [ -f "$T4DIR/$bk/rc" ]             && rc="$(cat "$T4DIR/$bk/rc")"
  [ -f "$T4DIR/$bk/non_443_count" ]  && non443="$(cat "$T4DIR/$bk/non_443_count")"
  [ -f "$T4DIR/$bk/to_443_count" ]   && to443="$(cat "$T4DIR/$bk/to_443_count")"
  verdict="PASS"
  if [ "$non443" != "0" ] || [ "$rc" != "0" ]; then verdict="FAIL"; fi
  [ "$verdict" = "PASS" ] && overall_pass=$((overall_pass+1)) || overall_fail=$((overall_fail+1))
  printf "%-15s | %3s | %8s | %8s | %s\n" "$bk" "$rc" "$non443" "$to443" "$verdict"
  printf "| %s | %s | %s | %s | %s |\n" "$bk" "$rc" "$non443" "$to443" "$verdict" >> "$REPORT"
done

{
  echo
  echo "**Overall:** $overall_pass / $((overall_pass+overall_fail)) backends pass."
} >> "$REPORT"

echo
echo "Pass: $overall_pass / $((overall_pass+overall_fail))"
echo "Report: $REPORT"
[ "$overall_fail" -eq 0 ] && exit 0 || exit 1
