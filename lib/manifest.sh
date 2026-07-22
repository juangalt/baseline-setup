#!/usr/bin/env bash
#
# lib/manifest.sh — parse and validate per-layer manifest.toml files (baseline-decomposition
# contract C2), plus read/write the C4 selection file (selected.toml). Sourced by
# baseline-setup.sh, never executed directly.
#
# Every consumer layer (baseline-shell, baseline-apps, baseline-desktop) has its own
# manifest_query that hardcodes its OWN manifest.toml path — baseline-setup is the first and only
# place that has to parse OTHER repos' manifests by path (C2: "consumer: baseline-setup reads all
# manifests; nothing else needs to"), so every function here takes an explicit path argument.
#
# Dynamic values (component ids, layer names) are passed to python3 as argv, never interpolated
# into the script text — this file is the one place in the whole baseline-* family that builds
# python3 snippets from data it doesn't fully control (a saved selected.toml, a caller-supplied
# id), so the sibling repos' "$1"-interpolation shortcut isn't safe to copy here.
#
# The `requires = { gui, atomic, family, de }` predicate (C2) is evaluated generically in
# visible_component_ids() below — no other script in the family does this today (each layer
# hand-codes its own gate checks per component instead); baseline-setup is the first and only
# consumer of the generic form (C2 again: "consumer: baseline-setup").

# manifest_query <path> <python-expr-fragment> [extra-argv...]
#
# Parses <path> as TOML into `data`, then evaluates <python-expr-fragment> against it. Extra argv
# is available to the fragment as `extra` (a list of strings) — use this instead of string
# interpolation for any value that isn't a literal owned by this file.
manifest_query() {
  local path="$1" expr="$2"
  shift 2
  python3 - "$path" "$@" <<PY
import sys
path = sys.argv[1]
extra = sys.argv[2:]
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
try:
    with open(path, "rb") as f:
        data = tomllib.load(f)
except FileNotFoundError:
    print(f"ERROR: no such file: {path}", file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"ERROR: could not parse {path}: {exc}", file=sys.stderr)
    sys.exit(1)
$expr
PY
}

# --- C2 manifest.toml readers -------------------------------------------------------------------

read_default_components() {  # path
  manifest_query "$1" 'print(",".join(c["id"] for c in data.get("component", []) if c.get("default") is True))'
}

valid_component_ids() {  # path
  manifest_query "$1" 'print(",".join(c["id"] for c in data.get("component", [])))'
}

component_label() {  # path id
  manifest_query "$1" '
for c in data.get("component", []):
    if c["id"] == extra[0]:
        print(c.get("label", c["id"]))
        break
else:
    print(extra[0])
' "$2"
}

# Component ids whose `requires` predicate is satisfied by the CURRENT platform.sh env (all keys
# present in `requires` must hold; an absent key imposes no constraint). PLATFORM_* is read from
# the process environment — platform.sh has already exported it by the time this runs; never
# re-derived here (the whole point of the shared C1 contract).
visible_component_ids() {  # path
  # Single-quoted deliberately — this is python source, not a bash string meant to expand.
  # shellcheck disable=SC2016
  manifest_query "$1" '
import os
plat = {
    "gui": os.environ.get("PLATFORM_GUI") == "1",
    "atomic": os.environ.get("PLATFORM_ATOMIC") == "1",
    "family": os.environ.get("PLATFORM_FAMILY", "unknown"),
    "de": os.environ.get("PLATFORM_DE", "none"),
}
import sys as _sys
def _list_predicate_holds(cid, key, req, plat_value):
    # requires.family / requires.de are documented as lists (C2: de = ["gnome"]) — a bare
    # string ("gnome" instead of ["gnome"]) would silently fall back to substring `in` semantics
    # instead of list membership, a real footgun (a manifest authoring typo would misbehave
    # instead of erroring). Treat anything but a list as hidden + warn, rather than guessing what
    # the author meant.
    val = req[key]
    if not isinstance(val, list):
        print(f"WARN: {cid}: requires.{key} must be a list (got {val!r}) — treating as hidden", file=_sys.stderr)
        return False
    return plat_value in val

def visible(c):
    req = c.get("requires") or {}
    cid = c.get("id", "?")
    if "gui" in req and bool(req["gui"]) != plat["gui"]:
        return False
    if "atomic" in req and bool(req["atomic"]) != plat["atomic"]:
        return False
    if "family" in req and not _list_predicate_holds(cid, "family", req, plat["family"]):
        return False
    if "de" in req and not _list_predicate_holds(cid, "de", req, plat["de"]):
        return False
    return True
print(",".join(c["id"] for c in data.get("component", []) if visible(c)))
'
}

# Dies (message on stderr, returns 1) listing valid ids on an unknown one; no-op on an empty csv.
validate_components() {  # path csv
  local path="$1" csv="$2"
  [ -n "$csv" ] || return 0
  local valid
  valid="$(valid_component_ids "$path")" || return 1
  local -a sel_ids valid_ids
  IFS=',' read -r -a sel_ids <<< "$csv"
  IFS=',' read -r -a valid_ids <<< "$valid"
  local id ok v
  for id in "${sel_ids[@]}"; do
    ok=0
    for v in "${valid_ids[@]}"; do [ "$id" = "$v" ] && ok=1 && break; done
    if [ "$ok" != 1 ]; then
      echo "unknown component id: '$id' (valid: $valid)" >&2
      return 1
    fi
  done
}

# Filter csv down to ids visible under the current platform; anything hidden is reported to
# stderr and dropped — never an error (C4: "Applying a saved selection whose component is hidden
# here = skip-and-report, never error").
filter_visible() {  # path csv
  local path="$1" csv="$2"
  [ -n "$csv" ] || { printf ''; return 0; }
  local visible
  visible="$(visible_component_ids "$path")" || return 1
  local -a sel_ids
  IFS=',' read -r -a sel_ids <<< "$csv"
  local id kept=""
  for id in "${sel_ids[@]}"; do
    case ",$visible," in
      *",$id,"*) kept="${kept:+$kept,}$id" ;;
      *) echo "skip: $id — not applicable on this platform" >&2 ;;
    esac
  done
  printf '%s' "$kept"
}

# Extend csv with the transitive closure of every selected component's `needs` (C2: "Picker
# auto-ticks needs transitively"). Best-effort — a `needs` on a component this platform hides is
# left in the output as-is; the caller (validate/filter) reports that separately.
resolve_needs() {  # path csv
  local path="$1" csv="$2"
  [ -n "$csv" ] || { printf ''; return 0; }
  manifest_query "$path" '
selected = set(extra[0].split(",")) if extra[0] else set()
by_id = {c["id"]: c for c in data.get("component", [])}
changed = True
while changed:
    changed = False
    for cid in list(selected):
        for need in by_id.get(cid, {}).get("needs", []):
            if need not in selected:
                selected.add(need)
                changed = True
print(",".join(sorted(selected)))
' "$csv"
}

# Prints one "a b" line per active conflicting pair in csv (both ids selected). Empty output = no
# conflicts. (C2: "refuses a selection with an active conflict".)
detect_conflicts() {  # path csv
  local path="$1" csv="$2"
  [ -n "$csv" ] || return 0
  manifest_query "$path" '
selected = set(extra[0].split(",")) if extra[0] else set()
by_id = {c["id"]: c for c in data.get("component", [])}
seen = set()
for cid in selected:
    for other in by_id.get(cid, {}).get("conflicts", []):
        if other in selected:
            pair = tuple(sorted((cid, other)))
            if pair not in seen:
                seen.add(pair)
                print(pair[0], pair[1])
' "$csv"
}

# --- C4 selected.toml I/O -------------------------------------------------------------------
#
# Same generic manifest_query harness, reused against selected.toml's different shape (one
# [<layer>] table per layer with a `components` array, instead of manifest.toml's [[component]]
# array) — the python side only cares what `data` looks like once parsed, not which contract it
# came from.

selection_has_layer() {  # sel_file layer
  [ -f "$1" ] || return 1
  local out
  out="$(manifest_query "$1" 'print("1" if extra[0] in data else "0")' "$2")" || return 1
  [ "$out" = "1" ]
}

selection_components() {  # sel_file layer — csv, empty if table absent/empty
  [ -f "$1" ] || { printf ''; return 0; }
  manifest_query "$1" 'print(",".join(data.get(extra[0], {}).get("components", [])))' "$2"
}

# L2 (meta-ai-dev) is a bare-`install.sh` pseudo-component, exempt from --components (ADR 0004
# D5) — its selected.toml table only ever carries `enabled`, never `components`.
selection_l2_enabled() {  # sel_file
  [ -f "$1" ] || { printf '0'; return 0; }
  manifest_query "$1" '
t = data.get("meta-ai-dev")
print("1" if (t is not None and t.get("enabled", True)) else "0")
'
}
