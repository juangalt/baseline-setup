#!/usr/bin/env bash
# Common setup helpers for the baseline-setup.sh test suite.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$TESTS_DIR/../baseline-setup.sh"
FIXTURES_DIR="$TESTS_DIR/fixtures"

load "$TESTS_DIR/bats.d/bats-support/load"
load "$TESTS_DIR/bats.d/bats-assert/load"

# Source baseline-setup.sh with main() stubbed so individual functions can be called directly.
# Relies on `main "$@"` being the last line of the script (family convention — see
# baseline-apps/baseline-desktop's own load_script_functions), and on BASELINE_SETUP_DIR (not
# BASH_SOURCE self-location, which doesn't resolve sanely under this sourcing trick) pointing the
# script's own lib/ sourcing at the real checkout.
load_script_functions() {
  export BASELINE_SETUP_DIR="$TESTS_DIR/.."
  # shellcheck disable=SC1090
  source <(head -n -1 "$SCRIPT"; printf 'main() { :; }\n')
}

# CODE_ROOT_DIR is this test's fixture "~/code" — BASELINE_SETUP_CODE_ROOT points the script at
# it. BASELINE_SHELL_PLATFORM_SH points at a nonexistent path by default (headless is the
# deterministic starting state) unless a test seeds the baseline-shell fixture, which carries its
# own platform.sh (tests/fixtures/repos/baseline-shell/platform.sh, controllable via
# FIXTURE_PLATFORM_* overrides) at the real code_root() resolution path.
isolate_environment() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CODE_ROOT_DIR="$BATS_TEST_TMPDIR/code"
  mkdir -p "$CODE_ROOT_DIR"
  export BASELINE_SETUP_CODE_ROOT="$CODE_ROOT_DIR"
  export BASELINE_SHELL_PLATFORM_SH="$BATS_TEST_TMPDIR/no-such-platform.sh"
  export BASELINE_SETUP_SELECTED_FILE="$BATS_TEST_TMPDIR/selected.toml"
  export BASELINE_SETUP_PROFILES_DIR="$FIXTURES_DIR/profiles"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : > "$STUB_LOG"
  unset STUB_FAIL_REPO || true
}

mock_gui_platform() {  # de — defaults gnome
  PLATFORM_GUI=1
  PLATFORM_FAMILY=debian
  PLATFORM_PKG=apt
  PLATFORM_ATOMIC=0
  PLATFORM_DE="${1:-gnome}"
}
mock_headless_platform() {
  PLATFORM_GUI=0; PLATFORM_FAMILY=unknown; PLATFORM_PKG=none; PLATFORM_ATOMIC=0; PLATFORM_DE=none
}

# Materializes every tests/fixtures/repos/<repo> under $CODE_ROOT_DIR/<repo> directly (bypasses
# the git clone step — for tests that only care about manifest/apply-engine behavior). A bare
# `.git` dir marks each as "already cloned" so clone_if_absent's own check short-circuits.
seed_fixture_repos() {
  local repo
  for repo in baseline-access baseline-shell baseline-apps baseline-desktop meta-ai-dev; do
    cp -r "$FIXTURES_DIR/repos/$repo" "$CODE_ROOT_DIR/$repo"
    mkdir -p "$CODE_ROOT_DIR/$repo/.git"
  done
}
