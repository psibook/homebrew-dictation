#!/usr/bin/env bash
# T6-brew-test.sh — does `brew test psibook/dictation/dictation-stack` pass?
#
# WHY: every Homebrew formula ships a `test do` block that lives in the
# formula itself. `brew test <formula>` is the standard, well-known way
# users sanity-check that a brew install was successful. T6 invokes it
# and asserts a clean exit.
#
# This is intentionally redundant with T1 (the formula's `test do`
# delegates to `dictate-verify`), but it exercises a different invocation
# surface — Homebrew's sandboxing, env scrubbing, and audit harness all
# wrap `brew test`. If T1 passes but T6 fails, something in the
# Homebrew test environment is incompatible with how dictate-verify
# resolves the fixture or whisperX path.
#
# Pass criterion: `brew test psibook/dictation/dictation-stack` exit 0.

set -uo pipefail
TEST_ID="T6-brew-test"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

# Sanity-check the tap is present.
if ! brew tap | grep -q '^psibook/dictation$'; then
  log_fail "tap psibook/dictation is not present"
  log_fail "  brew tap psibook/dictation"
  exit 1
fi
if ! brew list psibook/dictation/dictation-stack >/dev/null 2>&1; then
  log_fail "dictation-stack is not installed"
  log_fail "  brew install psibook/dictation/dictation-stack"
  exit 1
fi

log_step "Running brew test psibook/dictation/dictation-stack..."

if capture_normalized T6-brew-test brew test psibook/dictation/dictation-stack; then
  log_pass "brew test exited 0"
  exit 0
fi
log_fail "brew test failed; see $RUN_DIR/T6-brew-test.log"
echo "  Last 15 lines:"
tail -15 "$RUN_DIR/T6-brew-test.log" | sed 's/^/    /'
exit 1
