#!/usr/bin/env bash
# T1-smoke.sh — does the basic install work end-to-end?
#
# WHY: this is the contract's done-criterion in one test. If T1 PASSes,
# the formula resolved its system deps, post_install installed the
# Python tools, the IFW rpath patch held, the demo fixture is on disk
# at the bundled location, whisperX runs, and the F29 byte-stable
# transcript hash matches.
#
# Source-contract analogue: tests/smoke.sh in psibook/gemma-on-vm.
# Difference: that one ran on the VM with /Volumes/My Shared Files/
# input. This one uses the tap-bundled fixture.

set -uo pipefail
TEST_ID="T1-smoke"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

log_step "Running dictate-verify against the bundled fixture..."

if capture_normalized T1-dictate-verify dictate-verify; then
  log_pass "dictate-verify exited 0 (strict transcript-hash match)"
  echo "  log: $RUN_DIR/T1-dictate-verify.log"
  exit 0
fi

# dictate-verify failed — investigate. Could be transient HF download,
# could be real divergence. The log is normalized so the user can paste
# it without leaking $HOME or $REMOTE_PATH.
log_fail "dictate-verify exited non-zero"
echo "  See: $RUN_DIR/T1-dictate-verify.log"
echo
echo "  Last 10 lines (normalized):"
tail -10 "$RUN_DIR/T1-dictate-verify.log" | sed 's/^/    /'
exit 1
