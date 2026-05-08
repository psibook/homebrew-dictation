#!/usr/bin/env bash
# common.sh — shared helpers for host-side tests.
#
# This file is sourced (not executed) by every Tn-*.sh under host-tests/.
# Provides:
#
#   - locate_fixture_dir    — find $(brew --prefix)/share/dictation-stack/
#                             with sane fallbacks across Apple Silicon and Intel
#   - locate_whisperx       — find whisperx CLI, prefer ~/.local/bin
#   - locate_whisper_cli    — find whisper-cli (whisper.cpp build)
#   - require_tool          — die loudly if a CLI is missing
#   - log_step              — pretty stderr step marker
#   - capture_normalized    — run a command, capture stdout+stderr, push
#                             through normalize-paths.sh, save to a log
#   - run_dir               — directory for THIS test run (set by run-all.sh
#                             OR auto-created if Tn is run standalone)

set -uo pipefail

# Resolve the directory of THIS file (lib/) and the tap root.
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HOST_TESTS_DIR="$(cd "${_COMMON_LIB_DIR}/.." && pwd)"
TAP_ROOT="$(cd "${_HOST_TESTS_DIR}/.." && pwd)"

NORMALIZE="${_COMMON_LIB_DIR}/normalize-paths.sh"

# Where each Tn-* test parks its log files. run-all.sh sets RUN_DIR before
# sourcing common.sh; standalone Tn invocations create their own.
if [ -z "${RUN_DIR:-}" ]; then
  RUN_DIR="${_HOST_TESTS_DIR}/runs/$(date +%Y-%m-%d-%H%M%S)-standalone"
  mkdir -p "$RUN_DIR"
fi

# ----- Pretty output --------------------------------------------------------
log_step() { printf '\033[1m[%s]\033[0m %s\n' "${TEST_ID:-test}" "$*" >&2; }
log_pass() { printf '\033[32m  PASS\033[0m %s\n' "$*" >&2; }
log_fail() { printf '\033[31m  FAIL\033[0m %s\n' "$*" >&2; }
log_warn() { printf '\033[33m  WARN\033[0m %s\n' "$*" >&2; }

# ----- Tool location --------------------------------------------------------
locate_fixture_dir() {
  local candidates=(
    "$(brew --prefix dictation-stack 2>/dev/null || true)/share/dictation-stack"
    "$(brew --prefix 2>/dev/null || true)/share/dictation-stack"
    "/opt/homebrew/share/dictation-stack"
    "/usr/local/share/dictation-stack"
    "${TAP_ROOT}/test-fixtures"
  )
  for d in "${candidates[@]}"; do
    [ -n "$d" ] || continue
    if [ -f "$d/demo-audio-for-gemma.wav" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

locate_whisperx() {
  local candidates=(
    "$(command -v whisperx 2>/dev/null || true)"
    "$HOME/.local/bin/whisperx"
  )
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

locate_whisper_cli() {
  local candidates=(
    "$(command -v whisper-cli 2>/dev/null || true)"
    "$(brew --prefix 2>/dev/null || true)/bin/whisper-cli"
    "/opt/homebrew/bin/whisper-cli"
    "/usr/local/bin/whisper-cli"
  )
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

require_tool() {
  local name="$1"; local locator="$2"
  local found
  if found="$($locator)"; then
    echo "$found"
    return 0
  fi
  log_fail "$name not found"
  case "$name" in
    whisperx|whisper|mlx_whisper|insanely-fast-whisper|mlx_vlm.generate)
      log_fail "  This is a user-scope Python tool (uv tool install)."
      log_fail "  If you ran \`brew install dictation-stack\`, the next required step is:"
      log_fail "    dictate-stack-install"
      log_fail "  See: https://github.com/psibook/homebrew-dictation#install"
      ;;
    whisper-cli)
      log_fail "  This is built from source by \`brew install dictation-stack\`."
      log_fail "    brew tap psibook/dictation && brew install dictation-stack"
      ;;
    *)
      log_fail "  Run: brew tap psibook/dictation && brew install dictation-stack"
      log_fail "       dictate-stack-install"
      ;;
  esac
  return 1
}

# ----- Capture-and-normalize ------------------------------------------------
# Usage: capture_normalized <log-name> <cmd...>
#
# Runs the command with stdout+stderr merged, saves the RAW output to
# $RUN_DIR/<log-name>.raw.log, then pipes it through normalize-paths.sh
# and saves the result to $RUN_DIR/<log-name>.log. Returns the command's
# exit code.
capture_normalized() {
  local name="$1"; shift
  local raw="$RUN_DIR/${name}.raw.log"
  local clean="$RUN_DIR/${name}.log"
  local rc=0

  ( "$@" ) >"$raw" 2>&1 || rc=$?
  "$NORMALIZE" <"$raw" >"$clean"
  return "$rc"
}

# Strict-normalize a captured raw log: re-runs normalize in --strict mode
# and FAILS the test if any /Users/ or /Volumes/ leaks survive.
assert_no_leaks() {
  local raw="$1"
  if ! "$NORMALIZE" --strict <"$raw" >/dev/null; then
    log_fail "path-portability leak in: $raw"
    return 1
  fi
  return 0
}

# ----- Determinism helper ---------------------------------------------------
# Compare two text files by SHA-256 of normalized content. Useful for
# checking that two whisperx runs produce byte-identical output even when
# the captures contain absolute paths that may legitimately differ.
sha256_normalized() {
  "$NORMALIZE" <"$1" | shasum -a 256 | awk '{print $1}'
}
