#!/usr/bin/env bash
#
# lib/picker.sh — the interactive gum checklist (contract C4/C5 step 6): one multi-select group
# per L1 layer, seeded from the existing selected.toml (if any) or the manifest's `default = true`
# set, `needs` resolved transitively, an active `conflict` refused outright. Writes the result to
# the selection file. Never invoked on the `--selection` path — gum isn't even bootstrapped there.
#
# This file's gum-facing functions (picker_layer, run_picker) are not exercised by the bats
# suite — they need a real TTY + gum binary, which CI doesn't have. The logic they lean on
# (read_default_components, visible_component_ids, resolve_needs, detect_conflicts) lives in
# lib/manifest.sh and *is* unit-tested there; keep new picker logic in terms of those pure
# functions rather than growing bespoke logic here that would go untested.

# csv_to_toml_array <csv> -> `"a", "b"` (empty csv -> empty string)
csv_to_toml_array() {
  local csv="$1"
  [ -n "$csv" ] || { printf ''; return 0; }
  local -a ids
  IFS=',' read -r -a ids <<< "$csv"
  local out="" id
  for id in "${ids[@]}"; do
    out="${out:+$out, }\"$id\""
  done
  printf '%s' "$out"
}

# Render one layer's checklist via `gum choose`. Prints the chosen csv (may be empty).
picker_layer() {  # repo manifest_path existing_csv
  local repo="$1" manifest="$2" existing="$3"
  local ids
  ids="$(visible_component_ids "$manifest")" || { echo "ERROR: could not read $manifest" >&2; return 1; }
  [ -n "$ids" ] || { printf ''; return 0; }

  local seed="$existing"
  [ -n "$seed" ] || seed="$(read_default_components "$manifest")"

  local -a id_arr opts=() selected_opts=()
  IFS=',' read -r -a id_arr <<< "$ids"
  local id label opt
  for id in "${id_arr[@]}"; do
    label="$(component_label "$manifest" "$id")"
    opt="$id — $label"
    opts+=("$opt")
    case ",$seed," in *",$id,"*) selected_opts+=("$opt") ;; esac
  done

  local -a chosen=()
  if [ "${#selected_opts[@]}" -gt 0 ]; then
    local sel_csv; sel_csv="$(IFS=,; printf '%s' "${selected_opts[*]}")"
    mapfile -t chosen < <(gum choose --no-limit --header="$repo" --selected="$sel_csv" "${opts[@]}")
  else
    mapfile -t chosen < <(gum choose --no-limit --header="$repo" "${opts[@]}")
  fi

  local csv="" line cid
  for line in "${chosen[@]}"; do
    [ -n "$line" ] || continue
    cid="${line%% — *}"
    csv="${csv:+$csv,}$cid"
  done
  printf '%s' "$csv"
}

# Full interactive picker run: one picker_layer() per LAYER_ROSTER entry (lib/apply.sh), an L2
# confirm prompt, `needs`/`conflicts` resolution per layer, then writes $1 (the selection file).
run_picker() {  # out_file
  local out="$1"
  mkdir -p "$(dirname "$out")"

  local tmp; tmp="$(mktemp)"
  local entry repo manifest existing csv resolved conflicts
  for entry in $LAYER_ROSTER; do
    repo="${entry%%:*}"
    manifest="$(code_root)/$repo/manifest.toml"
    if [ ! -r "$manifest" ]; then
      echo "WARN $repo: no manifest.toml at $manifest — skipping in picker" >&2
      continue
    fi
    existing="$(selection_components "$out" "$repo")"
    csv="$(picker_layer "$repo" "$manifest" "$existing")" || { rm -f "$tmp"; return 1; }
    resolved="$(resolve_needs "$manifest" "$csv")"
    conflicts="$(detect_conflicts "$manifest" "$resolved")"
    if [ -n "$conflicts" ]; then
      echo "ERROR: $repo: conflicting components both selected:" >&2
      printf '  %s\n' "$conflicts" >&2
      rm -f "$tmp"
      return 1
    fi
    {
      printf '[%s]\n' "$repo"
      printf 'components = [%s]\n\n' "$(csv_to_toml_array "$resolved")"
    } >> "$tmp"
  done

  local l2_enabled=1
  gum confirm "Install the meta-ai-dev AI/dev layer (L2)?" --default=yes && l2_enabled=1 || l2_enabled=0
  {
    printf '[meta-ai-dev]\n'
    printf 'enabled = %s\n' "$([ "$l2_enabled" = 1 ] && echo true || echo false)"
  } >> "$tmp"

  mv "$tmp" "$out"
  echo "wrote $out"
}
