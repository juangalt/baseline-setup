#!/usr/bin/env bash
#
# lib/apply.sh — the apply engine (contract C3/C5): invoke each layer's installer with
# `--components <ids>` in the fixed stage order. The single install path — both the interactive
# gum picker and the non-interactive `--selection` front-end feed this, never install anything
# themselves.
#
# Static layer roster (ADR 0004 D6) — the only place a layer's repo/script/invocation-style is
# named. Deliberately just repo:script:invoke triples, never a component id: baseline-setup may
# know the manifest *schema*, the stage *order*, and each script's calling convention, never a
# layer's *contents* (ARCHITECTURE.md "The boundary"). L1a -> L1b -> L1c order; L2 (meta-ai-dev)
# is handled separately below, it isn't --components-shaped.
#
# `invoke` is "install" (baseline-apps.sh/baseline-desktop.sh: `<script> install --components
# <csv> [--dry-run]`, siblings to their own `status`/`push` subcommands) or "flags"
# (baseline-shell/bootstrap.sh: bare `<script> --components <csv> [--dry-run]`, no subcommand —
# it never grew status/push, so --components is just a flag on the script itself, not one verb
# among several). Found the hard way: Phase 6's own bats fixtures accepted both shapes loosely,
# so a hardcoded "install" for every layer shipped without any test catching it — the real
# bootstrap.sh rejects an "install" argument outright ("unknown arg: install"). Caught during
# Phase 7's real-hardware validation, not by the test suite.
LAYER_ROSTER="baseline-shell:bootstrap.sh:flags baseline-apps:baseline-apps.sh:install baseline-desktop:baseline-desktop.sh:install"
L2_REPO="meta-ai-dev"
L2_SCRIPT="install.sh"

code_root() { printf '%s' "${BASELINE_SETUP_CODE_ROOT:-$HOME/code}"; }

# Apply one L1 layer: filter the saved selection down to what's visible on this platform
# (skip-and-report anything hidden), then invoke the script per its own calling convention
# (see LAYER_ROSTER's comment for "install" vs "flags"). Never dies — a missing clone/manifest or
# a failing installer is reported and the caller decides whether to keep going (contract C3's
# "one item's failure doesn't abort the batch", scaled up to the engine's own layer-by-layer loop
# per the post-Phase-4 plan review).
apply_layer() {  # repo script invoke selected_csv dry
  local repo="$1" script="$2" invoke="$3" selected="$4" dry="$5"
  local dir; dir="$(code_root)/$repo"
  local manifest="$dir/manifest.toml"

  if [ ! -d "$dir" ]; then
    echo "WARN $repo: not cloned at $dir — skipping" >&2
    return 1
  fi
  if [ ! -r "$manifest" ]; then
    echo "WARN $repo: no manifest.toml at $manifest — skipping" >&2
    return 1
  fi

  # Validate against every declared id BEFORE filtering by platform — an unknown/misspelled id
  # must fail with "unknown component id", not silently fall into filter_visible's generic "not
  # applicable on this platform" (which is reserved for ids that exist but are hidden here).
  validate_components "$manifest" "$selected" || { echo "WARN $repo: invalid component selection — skipping" >&2; return 1; }

  local visible
  visible="$(filter_visible "$manifest" "$selected")" || { echo "WARN $repo: could not read manifest.toml — skipping" >&2; return 1; }

  local -a cmd=(bash "$dir/$script")
  [ "$invoke" = "install" ] && cmd+=(install)
  cmd+=(--components "$visible")
  [ "$dry" = 1 ] && cmd+=(--dry-run)
  echo "==> $repo: ${cmd[*]:2}"
  if "${cmd[@]}"; then
    return 0
  fi
  echo "WARN $repo: install exited non-zero — continuing with the remaining layers" >&2
  return 1
}

# L2 (meta-ai-dev): a bare install.sh, exempt from --components (ADR 0004 D5). enabled=1/0 comes
# from selection_l2_enabled — the caller resolves that; this function just runs or skips.
apply_l2() {  # enabled dry
  local enabled="$1" dry="$2"
  if [ "$enabled" != 1 ]; then
    echo "skip: $L2_REPO (L2) — not selected"
    return 0
  fi
  local dir; dir="$(code_root)/$L2_REPO"
  if [ ! -d "$dir" ]; then
    echo "WARN $L2_REPO: not cloned at $dir — skipping" >&2
    return 1
  fi
  echo "==> $L2_REPO: $L2_SCRIPT"
  local -a cmd=(bash "$dir/$L2_SCRIPT")
  [ "$dry" = 1 ] && cmd+=(--dry-run)
  if "${cmd[@]}"; then
    return 0
  fi
  echo "WARN $L2_REPO: install exited non-zero — continuing" >&2
  return 1
}

# Print the ordered (repo, components) apply plan a selection file resolves to, one "repo|csv"
# line per L1 layer with a present table, plus "meta-ai-dev|<enabled>" last — this is what the
# "identical apply plan" acceptance check (Phase 6 "Done when") compares between the interactive
# and --selection paths. Pure/no side effects — does not require platform.sh to be sourced with
# real values (tests can stub PLATFORM_* directly).
apply_plan() {  # sel_file
  local sel_file="$1"
  local entry repo csv
  for entry in $LAYER_ROSTER; do
    repo="${entry%%:*}"
    if ! selection_has_layer "$sel_file" "$repo"; then
      echo "$repo|<skip: no table>"
      continue
    fi
    csv="$(selection_components "$sel_file" "$repo")"
    echo "$repo|$csv"
  done
  echo "$L2_REPO|$(selection_l2_enabled "$sel_file")"
}

# Run the whole apply plan from a C4 selection file, in fixed stage order. Never aborts on one
# layer's failure — accumulates and reports at the end, exits non-zero if anything failed.
apply_selection() {  # sel_file dry
  local sel_file="$1" dry="$2"
  local failed=0
  local entry repo script invoke csv

  for entry in $LAYER_ROSTER; do
    IFS=':' read -r repo script invoke <<< "$entry"
    if ! selection_has_layer "$sel_file" "$repo"; then
      echo "skip: $repo (no selection table — layer skipped, ADR 0004 D8)"
      continue
    fi
    csv="$(selection_components "$sel_file" "$repo")"
    if [ -z "$csv" ]; then
      echo "skip: $repo (empty selection — fully-deselected layer)"
      continue
    fi
    apply_layer "$repo" "$script" "$invoke" "$csv" "$dry" || failed=1
  done

  apply_l2 "$(selection_l2_enabled "$sel_file")" "$dry" || failed=1

  return "$failed"
}
