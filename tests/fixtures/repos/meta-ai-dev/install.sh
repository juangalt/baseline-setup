#!/usr/bin/env bash
# Stub L2 install.sh for baseline-setup's bats fixtures — bare invocation, no --components
# (ADR 0004 D5, the L2 pseudo-component is exempt from the C3 --components contract).
set -euo pipefail
dry=0
[ "${1:-}" = "--dry-run" ] && dry=1
me="$(basename "$(dirname "${BASH_SOURCE[0]}")")"
[ -n "${STUB_LOG:-}" ] && printf '%s install dry=%s\n' "$me" "$dry" >> "$STUB_LOG"
if [ "${STUB_FAIL_REPO:-}" = "$me" ]; then
  echo "stub: simulated failure for $me" >&2
  exit 1
fi
exit 0
