#!/usr/bin/env bash
# Generic stub layer installer for baseline-setup's bats fixtures. Mirrors the real
# `install --components <csv> [--dry-run]` shape (contract C3) without doing anything: logs the
# call to $STUB_LOG (if set) and exits 0 — unless $STUB_FAIL_REPO names this stub's own directory
# basename, in which case it exits 1 (used for the layer-batch-failure-tolerance test).
#
# Not sourced/copied automatically — each fixture repo dir has its own copy under its real
# script filename (bootstrap.sh, baseline-apps.sh, baseline-desktop.sh), identical content.
set -euo pipefail
cmd="${1:-}"; shift || true
components=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --components) components="$2"; shift 2 ;;
    --components=*) components="${1#--components=}"; shift ;;
    --dry-run) dry=1; shift ;;
    *) shift ;;
  esac
done
me="$(basename "$(dirname "${BASH_SOURCE[0]}")")"
if [ -n "${STUB_LOG:-}" ]; then
  printf '%s %s components=%s dry=%s\n' "$me" "$cmd" "$components" "$dry" >> "$STUB_LOG"
fi
if [ "${STUB_FAIL_REPO:-}" = "$me" ]; then
  echo "stub: simulated failure for $me" >&2
  exit 1
fi
exit 0
