#!/usr/bin/env bash
# Stub layer installer — FLAGS style, matching the real bootstrap.sh: no subcommand, just flags
# on the script itself (contract C3's bare `--components <csv> [--dry-run]`). Deliberately
# STRICT — rejects anything else (including a leading "install") so a regression back to
# hardcoding an "install" subcommand for every layer (the real Phase 7 bug this fixture exists
# to catch) fails loudly instead of being silently tolerated.
set -euo pipefail
components=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --components) components="$2"; shift 2 ;;
    --components=*) components="${1#--components=}"; shift ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown arg: $1 (bootstrap.sh takes no subcommand)" >&2; exit 2 ;;
  esac
done
me="$(basename "$(dirname "${BASH_SOURCE[0]}")")"
if [ -n "${STUB_LOG:-}" ]; then
  printf '%s install components=%s dry=%s\n' "$me" "$components" "$dry" >> "$STUB_LOG"
fi
if [ "${STUB_FAIL_REPO:-}" = "$me" ]; then
  echo "stub: simulated failure for $me" >&2
  exit 1
fi
exit 0
