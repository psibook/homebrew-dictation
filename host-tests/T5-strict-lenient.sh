#!/usr/bin/env bash
# T5-strict-lenient.sh — does dictate-verify --lenient agree with strict?
#
# WHY: dictate-verify ships two modes:
#
#   strict  — exact transcript SHA-256 match against the F29 reference.
#             Fragile to whisperX version drift but proves byte-for-byte
#             reproducibility.
#   lenient — substring-presence match (must contain "voice memo",
#             an MLXVLM-shaped token, and "Gemma"). Survives small
#             segmentation/punctuation drift.
#
# T5 runs both and asserts:
#
#   - on a happy install, strict PASSes (and lenient implicitly does too)
#   - if strict ever FAILs, lenient should still PASS — otherwise we
#     have a real content divergence, not just whisperX version drift
#
# Pass criterion: at least one of the two passes. Strict + lenient PASS
# means F29 holds. Lenient-only PASS means whisperX upgraded but the
# install is otherwise correct.

set -uo pipefail
TEST_ID="T5-strict-lenient"

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

# require_tool wrapper for dictate-verify
DV="$(command -v dictate-verify 2>/dev/null || true)"
[ -z "$DV" ] && DV="$(brew --prefix 2>/dev/null)/bin/dictate-verify"
if [ ! -x "$DV" ]; then
  log_fail "dictate-verify not found — is the formula installed?"
  exit 1
fi

log_step "Running dictate-verify (strict)..."
strict_rc=0
capture_normalized T5-strict "$DV" || strict_rc=$?
if [ "$strict_rc" -eq 0 ]; then
  log_pass "strict passed"
fi

log_step "Running dictate-verify --lenient..."
lenient_rc=0
capture_normalized T5-lenient "$DV" --lenient || lenient_rc=$?
if [ "$lenient_rc" -eq 0 ]; then
  log_pass "lenient passed"
fi

# Both PASS: ideal — strict implies lenient.
if [ "$strict_rc" -eq 0 ] && [ "$lenient_rc" -eq 0 ]; then
  log_pass "strict + lenient agree (F29 byte-stable hash holds)"
  exit 0
fi

# Strict FAIL but lenient PASS: whisperX likely drifted; content correct.
if [ "$strict_rc" -ne 0 ] && [ "$lenient_rc" -eq 0 ]; then
  log_warn "strict FAILed but lenient PASSed"
  log_warn "  → whisperX may have upgraded; transcript content is correct."
  log_warn "  → If reproducibility matters for your use case, pin whisperX."
  exit 0
fi

# Strict PASS but lenient FAIL: impossible if expected.txt is well-formed.
if [ "$strict_rc" -eq 0 ] && [ "$lenient_rc" -ne 0 ]; then
  log_fail "strict PASSed but lenient FAILed — fixture inconsistency"
  log_fail "  Bug in dictate-verify --lenient or in expected.txt itself."
  exit 1
fi

log_fail "both strict and lenient failed — content divergence, not version drift"
echo
echo "  See $RUN_DIR/T5-strict.log and $RUN_DIR/T5-lenient.log."
exit 1
