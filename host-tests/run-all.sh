#!/usr/bin/env bash
# run-all.sh — run every host-side test in sequence and report.
#
# Usage:
#   host-tests/run-all.sh                # run T1..T6 in order
#   host-tests/run-all.sh T1 T3 T5       # run a subset
#   host-tests/run-all.sh --list         # list available tests
#   host-tests/run-all.sh --strict       # fail if any output has unhandled paths
#
# Output: each test logs to host-tests/runs/<timestamp>/Tn-*.log.
# All captured output is normalized (see lib/normalize-paths.sh) so
# logs are safe to share without leaking $HOME or $REMOTE_PATH.

set -uo pipefail

HOST_TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${HOST_TESTS_DIR}/runs/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$RUN_DIR"
export RUN_DIR

ALL_TESTS=(
  T1-smoke
  T2-repeat
  T3-resource
  T4-offline
  T5-strict-lenient
  T6-brew-test
)

usage() {
  cat <<EOF
Usage: run-all.sh [--list] [--strict] [TEST...]

  --list        List available tests and exit.
  --strict      After all tests, scan every captured log with
                normalize-paths.sh --strict; fail if any /Users/ or
                /Volumes/ patterns survive.
  -h, --help    This help.

Available tests:
$(printf '  %s\n' "${ALL_TESTS[@]}")
EOF
}

STRICT=0
TESTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) printf '%s\n' "${ALL_TESTS[@]}"; exit 0 ;;
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) TESTS+=("$1"); shift ;;
  esac
done

[ "${#TESTS[@]}" -eq 0 ] && TESTS=("${ALL_TESTS[@]}")

# Resolve test names → script paths.
resolve() {
  local name="$1"
  case "$name" in
    T1|T1-smoke)             echo "${HOST_TESTS_DIR}/T1-smoke.sh" ;;
    T2|T2-repeat)            echo "${HOST_TESTS_DIR}/T2-repeat.sh" ;;
    T3|T3-resource)          echo "${HOST_TESTS_DIR}/T3-resource.sh" ;;
    T4|T4-offline)           echo "${HOST_TESTS_DIR}/T4-offline.sh" ;;
    T5|T5-strict-lenient)    echo "${HOST_TESTS_DIR}/T5-strict-lenient.sh" ;;
    T6|T6-brew-test)         echo "${HOST_TESTS_DIR}/T6-brew-test.sh" ;;
    *)                       echo "" ;;
  esac
}

echo "================================================================"
echo " psibook/dictation host-tests"
echo " RUN_DIR: $RUN_DIR"
echo "================================================================"
echo

results=()
for name in "${TESTS[@]}"; do
  script="$(resolve "$name")"
  if [ -z "$script" ] || [ ! -x "$script" ]; then
    echo "  SKIP  $name (not found or not executable)"
    results+=("SKIP $name")
    continue
  fi
  echo
  printf '\033[1m──── %s ────\033[0m\n' "$name"
  if "$script"; then
    results+=("PASS $name")
  else
    results+=("FAIL $name")
  fi
done

echo
echo "================================================================"
echo " SUMMARY"
echo "================================================================"
pass=0; fail=0; skip=0
for r in "${results[@]}"; do
  case "$r" in
    PASS*) printf '\033[32m  %s\033[0m\n' "$r"; pass=$((pass+1)) ;;
    FAIL*) printf '\033[31m  %s\033[0m\n' "$r"; fail=$((fail+1)) ;;
    *)     printf '\033[33m  %s\033[0m\n' "$r"; skip=$((skip+1)) ;;
  esac
done
echo
echo "  $pass passed, $fail failed, $skip skipped"
echo "  logs: $RUN_DIR"

# Optional strict scan: fail if any captured log has unhandled paths.
if [ "$STRICT" -eq 1 ]; then
  echo
  echo "──── strict path-portability scan ────"
  leak_count=0
  for log in "$RUN_DIR"/*.log; do
    [ -f "$log" ] || continue
    if ! "${HOST_TESTS_DIR}/lib/normalize-paths.sh" --strict <"$log" >/dev/null 2>&1; then
      printf '\033[31m  LEAK\033[0m %s\n' "$log"
      leak_count=$((leak_count+1))
    fi
  done
  if [ "$leak_count" -gt 0 ]; then
    echo
    printf '\033[31m  STRICT FAIL: %d log(s) leaked unhandled paths\033[0m\n' "$leak_count"
    exit 1
  fi
  printf '\033[32m  STRICT PASS: every log normalized cleanly\033[0m\n'
fi

# Overall exit: 0 only if every test passed.
[ "$fail" -eq 0 ] && exit 0 || exit 1
