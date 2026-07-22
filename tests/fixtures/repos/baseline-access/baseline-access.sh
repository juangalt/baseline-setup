#!/usr/bin/env bash
# Stub baseline-access.sh for baseline-setup's bats fixtures — no real Bitwarden/network calls.
set -euo pipefail
cmd="${1:-provision}"
[ -n "${STUB_LOG:-}" ] && printf 'baseline-access %s\n' "$cmd" >> "$STUB_LOG"
exit 0
