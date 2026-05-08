#!/usr/bin/env bash
# normalize-paths.sh — replace machine-specific paths with portable env vars.
#
# WHY: test artifacts, log files, and tool stdout/stderr commonly embed
# absolute paths that look reproducible but aren't. Two patterns appear
# in captures from this tap's source contract (gemma-on-vm):
#
#   /Users/<username>/.local/...        (current user's home)
#   /Volumes/My Shared Files/...        (UTM courier mount on a VM)
#
# Neither will exist on someone else's machine. Normalizing them at
# test-output capture time means the saved logs read the same on every
# host AND a future Claude session can spot-check captures from a
# different machine without seeing fake "leaked" paths everywhere.
#
# USAGE
#
#   tool-that-prints-paths | host-tests/lib/normalize-paths.sh
#   host-tests/lib/normalize-paths.sh < input.log > input.normalized.log
#   host-tests/lib/normalize-paths.sh --strict < input.log
#
# REPLACEMENTS
#
#   $HOME (env value)                        -> literal '$HOME'
#   /Volumes/My Shared Files                 -> literal '$REMOTE_PATH'
#
# STRICT MODE (--strict)
#
#   After applying the two replacements above, scan for surviving
#   /Users/ or /Volumes/ patterns. Any survivor means we found a
#   path-portability leak the filter doesn't know about. Strict mode
#   exits 1 in that case and prints the offending lines on stderr —
#   used in CI / test-harness so new leaks fail loud.
#
#   Without --strict the filter just emits the substituted output and
#   doesn't validate. Use that mode for ad-hoc cleanup (e.g.,
#   pre-publish sanitizing of an arbitrary log).

set -euo pipefail

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed 's/^# \?//' | head -n -1
}

STRICT=0
case "${1:-}" in
  --strict) STRICT=1; shift ;;
  -h|--help) usage; exit 0 ;;
esac

if [ -z "${HOME:-}" ]; then
  echo "normalize-paths: HOME env var unset; cannot substitute" >&2
  exit 2
fi

# Escape forward slashes and ampersands in $HOME for use as sed replacement target.
home_escaped="$(printf '%s\n' "$HOME" | sed 's/[][\/.^$*]/\\&/g')"

if [ "$STRICT" -eq 1 ]; then
  # Capture into a temp so we can re-scan after substitution.
  tmp="$(mktemp -t normalize-paths-XXXXXX)"
  trap 'rm -f "$tmp"' EXIT
  sed \
    -e "s|${home_escaped}|\$HOME|g" \
    -e "s|/Volumes/My Shared Files|\$REMOTE_PATH|g" \
    > "$tmp"
  cat "$tmp"

  # Strict scan: look for any /Users/<word>/ or /Volumes/ that wasn't caught.
  if grep -nE '/(Users|Volumes)/[A-Za-z0-9_.-]+' "$tmp" >/dev/null 2>&1; then
    echo >&2
    echo "normalize-paths: STRICT failure — unhandled path patterns survived:" >&2
    grep -nE '/(Users|Volumes)/[A-Za-z0-9_.-]+' "$tmp" | head -20 | sed 's/^/  /' >&2
    exit 1
  fi
  exit 0
fi

# Non-strict: just emit the substituted stream.
sed \
  -e "s|${home_escaped}|\$HOME|g" \
  -e "s|/Volumes/My Shared Files|\$REMOTE_PATH|g"
