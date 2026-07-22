#!/usr/bin/env bash
# Stub layer installer — INSTALL-subcommand style, matching the real baseline-apps.sh:
# `<script> install --components <csv> [--dry-run]`, sibling to its own `status`/`push`
# subcommands. Deliberately STRICT — rejects anything but a leading "install" so a regression to
# a bare-flags invocation (the mirror image of the real Phase 7 bootstrap.sh bug) fails loudly.
set -euo pipefail
cmd="${1:-}"
if [ "$cmd" != "install" ]; then
  echo "unknown command: $cmd (expected 'install')" >&2
  exit 2
fi
shift
components=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --components) components="$2"; shift 2 ;;
    --components=*) components="${1#--components=}"; shift ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
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
