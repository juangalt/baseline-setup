#!/usr/bin/env bash
#
# baseline-setup.sh — the orchestrator: a component picker + apply engine over every baseline-*
# layer's manifest.toml (baseline-decomposition ADR 0003). Holds NO layer logic of its own — see
# ARCHITECTURE.md "The boundary". Clones the layer repos, sources the shared platform.sh
# detection contract, then either renders a gum checklist or loads a named `--selection`, and
# invokes each layer's own installer with its slice via `--components` (contract C3).
#
# Usage:
#   baseline-setup.sh                             Interactive: gum picker, then apply
#   baseline-setup.sh --selection <name> [--yes]   Non-interactive: apply profiles/<name>.toml
#   baseline-setup.sh --dry-run                    Print the apply plan; install nothing
#   baseline-setup.sh --help
#
# --selection <name> reads profiles/<name>.toml from THIS checkout (error if absent), copies it
# to the selection file, and applies it — no gum, no TTY required. --yes is required outside a
# TTY (a non-interactive run with no way to prompt must never silently proceed); with a TTY and
# no --yes, it asks for confirmation instead.
#
# --dry-run's meaning is deliberately path-dependent, not a single global flag threaded uniformly:
#   --selection ... --dry-run   skips the ENTIRE bootstrap prefix (no clone, no Bitwarden login,
#                                no credential writes) and prints the plan straight from the
#                                profile file via apply_plan() — genuinely "touch nothing," works
#                                on a completely fresh, uncloned box.
#   (interactive) --dry-run     still clones + bootstraps gum (rendering a real checklist needs
#                                the live manifests and gum on disk — there is no way to preview a
#                                picker without them), but stops after printing the plan instead
#                                of invoking any layer's installer.
# Neither path ever calls a layer's own --dry-run — the "plan" is baseline-setup's own C4
# selection-to-repo|components mapping (apply_plan()), not each installer's internal preview.

set -euo pipefail

RD="${BASELINE_SETUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/manifest.sh
. "$RD/lib/manifest.sh"
# shellcheck source=lib/apply.sh
. "$RD/lib/apply.sh"
# shellcheck source=lib/gum-bootstrap.sh
. "$RD/lib/gum-bootstrap.sh"
# shellcheck source=lib/picker.sh
. "$RD/lib/picker.sh"

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*" >&2; }
die()  { printf 'ERROR %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^#\( \|$\)//'; }

# ── Step 0: L0 access-policy guidance (informational, non-blocking — baseline-setup performs no
# enrolment itself; ARCHITECTURE.md § L0). ------------------------------------------------------
print_l0_guidance() {
  say ""
  say "Fleet access (informational — run manually if this machine needs it):"
  say "  Personal machine -> make it a control node (run on the machine itself):"
  say "    fleet control-node bootstrap"
  say "  Fleet host (LXC, server) -> add it from an existing control node:"
  say "    fleet host add <name> --deploy"
  say ""
}

# ── Step 1: python3 (parser dep, ADR 0004 D1); clone the PUBLIC baseline-access repo and RUN it
# -> GitHub key on disk. Mandatory prerequisite, not a component. -------------------------------
BASELINE_ACCESS_REPO="${BASELINE_SETUP_ACCESS_REPO:-https://github.com/juangalt/baseline-access.git}"

ensure_python3() {
  command -v python3 >/dev/null 2>&1 \
    || die "python3 not found — required to read manifest.toml (ADR 0004 D1); install it and retry"
}

# Clone-if-absent; an existing checkout is left completely untouched (no `git pull` against a
# possibly-dirty dev tree) — reports which path was taken either way.
clone_if_absent() {  # repo_url dest_dir
  local url="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    say "ok   $(basename "$dest") already cloned at $dest — leaving it untouched"
    return 0
  fi
  say "==> cloning $(basename "$dest") -> $dest"
  mkdir -p "$(dirname "$dest")"
  git clone --depth=1 -q "$url" "$dest" || die "git clone failed: $url"
}

bootstrap_access() {
  ensure_python3
  local dest; dest="$(code_root)/baseline-access"
  clone_if_absent "$BASELINE_ACCESS_REPO" "$dest"
  say "==> running baseline-access.sh provision"
  bash "$dest/baseline-access.sh" provision
}

# ── Step 2: clone the private layer repos. -------------------------------------------------------
PRIVATE_REPOS="baseline-shell baseline-apps baseline-desktop meta-ai-dev"
BASELINE_REPO_BASE="${BASELINE_SETUP_REPO_BASE:-https://github.com/juangalt}"

clone_private_repos() {
  local repo
  for repo in $PRIVATE_REPOS; do
    clone_if_absent "$BASELINE_REPO_BASE/$repo.git" "$(code_root)/$repo"
  done
}

# ── Step 3: source baseline-shell/platform.sh (now present) — C1. Defaults set BEFORE the
# conditional source, not only in the "missing" branch (the sourcing idiom the post-Phase-4 review
# flagged: a present-but-partial platform.sh must degrade to headless, never leave a var unbound).
PLATFORM_GUI=0
PLATFORM_FAMILY=unknown
PLATFORM_PKG=none
PLATFORM_ATOMIC=0
PLATFORM_DE=none
# Exported here, not only by platform.sh's own `export` line — lib/manifest.sh's
# visible_component_ids() reads these via a python3 subprocess's os.environ, which only sees
# exported vars. Without this, a present-but-partial platform.sh failure would silently pass
# nothing through to python3 (it would happen to still degrade headless-safe today only because
# python3's own fallback defaults were deliberately written to match these — don't rely on that
# coincidence holding across future edits to either side).
export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE

source_platform() {
  local sh="${BASELINE_SHELL_PLATFORM_SH:-$(code_root)/baseline-shell/platform.sh}"
  if [ -r "$sh" ]; then
    # shellcheck source=/dev/null
    . "$sh" || warn "baseline-shell/platform.sh failed while sourcing — assuming headless (no GUI)"
  else
    warn "baseline-shell/platform.sh not found at $sh — assuming headless (no GUI); clone baseline-shell for accurate detection"
  fi
}

# ── Steps 4–7: manifest read (lazy, inside apply/picker) + gum bootstrap + select + apply. ------

SELECTED_FILE="${BASELINE_SETUP_SELECTED_FILE:-$HOME/.config/baseline-setup/selected.toml}"
PROFILES_DIR="${BASELINE_SETUP_PROFILES_DIR:-$RD/profiles}"

run_noninteractive() {  # selection_name yes dry
  local name="$1" yes="$2" dry="$3"

  local profile="$PROFILES_DIR/$name.toml"
  [ -f "$profile" ] || die "no such selection: $PROFILES_DIR/$name.toml"

  # --dry-run is a pure preview — it never applies anything, so it never needs --yes or a
  # confirmation prompt (checked BEFORE the yes/confirm gate below, not after: gating a
  # read-only preview behind "apply this? [y/N]" would be actively misleading). apply_plan()
  # reads only the profile itself (no manifest.toml, no platform.sh, no clone) — "print the
  # plan, touch nothing" means exactly that, not "run the real apply with --dry-run threaded
  # through" (that path requires the layer repos to already be cloned, which a fresh-box
  # preview can't assume).
  if [ "$dry" = 1 ]; then
    say "Apply plan for --selection $name (preview only — nothing cloned, authenticated, or installed):"
    apply_plan "$profile"
    return 0
  fi

  if [ "$yes" != 1 ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      printf 'Apply selection %s to this machine? [y/N] ' "$name"
      local ans; read -r ans
      case "$ans" in y|Y|yes|YES) ;; *) die "aborted" ;; esac
    else
      die "--selection requires --yes when not running in a terminal"
    fi
  fi

  print_l0_guidance
  bootstrap_access
  clone_private_repos
  source_platform

  mkdir -p "$(dirname "$SELECTED_FILE")"
  cp "$profile" "$SELECTED_FILE"

  apply_selection "$SELECTED_FILE" 0
}

run_interactive() {  # dry
  local dry="$1"

  # Unlike the non-interactive path, --dry-run here can't skip cloning: rendering the checklist
  # itself needs the live manifests (and gum) on disk. --dry-run instead means "pick, preview,
  # but don't invoke any layer's installer."
  print_l0_guidance
  bootstrap_access
  clone_private_repos
  source_platform

  local gum_bin
  gum_bin="$(gum_bootstrap)" \
    || die "could not obtain gum — use --selection <name> --yes instead (see profiles/)"
  local gum_dir; gum_dir="$(dirname "$gum_bin")"
  export PATH="$gum_dir:$PATH"

  run_picker "$SELECTED_FILE"

  if [ "$dry" = 1 ]; then
    say "Apply plan (preview only — nothing installed):"
    apply_plan "$SELECTED_FILE"
    return 0
  fi

  apply_selection "$SELECTED_FILE" 0
}

main() {
  local selection="" yes=0 dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --selection)
        [ $# -ge 2 ] || die "--selection requires a value (a profiles/<name>.toml basename)"
        selection="$2"; shift 2 ;;
      --selection=*) selection="${1#--selection=}"; shift ;;
      --yes) yes=1; shift ;;
      --dry-run) dry=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown arg: $1 (try --help)" ;;
    esac
  done

  if [ -n "$selection" ]; then
    run_noninteractive "$selection" "$yes" "$dry"
  elif [ -t 0 ] && [ -t 1 ]; then
    run_interactive "$dry"
  else
    die "no TTY and no --selection given — pass --selection <name> --yes for non-interactive runs (see profiles/)"
  fi
}

main "$@"
