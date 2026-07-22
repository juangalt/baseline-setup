#!/usr/bin/env bats
# Integration tests — exec baseline-setup.sh as a real subprocess (bats' `run`), no sourcing
# tricks. Covers the Phase 6 plan's required bats coverage: mock manifests, a `--selection --yes`
# golden run (with git mocks for the clone step), empty-selection skip, headless auto-hide, and
# the non-TTY guard.

load '../helpers/common.bash'
load '../helpers/mocks.bash'

setup() {
  isolate_environment
  setup_mock_bin
}

@test "--help exits 0 and documents --selection" {
  run bash "$SCRIPT" --help
  assert_success
  assert_output --partial "--selection"
}

@test "unknown flag exits non-zero with a hint" {
  run bash "$SCRIPT" --bogus
  assert_failure
  assert_output --partial "unknown arg"
}

@test "no TTY and no --selection errors with the --selection hint instead of hanging" {
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "--selection"
}

@test "--selection of a name with no profiles/<name>.toml errors" {
  run bash "$SCRIPT" --selection does-not-exist --yes
  assert_failure
  assert_output --partial "no such selection"
}

@test "--selection without --yes, no TTY, errors (never silently proceeds)" {
  run bash "$SCRIPT" --selection golden
  assert_failure
  assert_output --partial "requires --yes"
}

@test "fresh box: --selection golden --yes clones every repo (git mock) and applies in stage order" {
  mock_git_clone_from_fixtures
  unset BASELINE_SHELL_PLATFORM_SH   # let it resolve to the freshly-cloned fixture's own platform.sh

  run bash "$SCRIPT" --selection golden --yes
  assert_success

  # The clone step actually ran (fresh $CODE_ROOT_DIR had nothing beforehand).
  [ -d "$CODE_ROOT_DIR/baseline-access/.git" ]
  [ -d "$CODE_ROOT_DIR/baseline-shell/.git" ]
  [ -d "$CODE_ROOT_DIR/baseline-apps/.git" ]
  [ -d "$CODE_ROOT_DIR/baseline-desktop/.git" ]
  [ -d "$CODE_ROOT_DIR/meta-ai-dev/.git" ]

  run cat "$STUB_LOG"
  assert_output --partial "baseline-access provision"
  assert_output --partial "baseline-shell install components=comp-a,comp-b dry=0"
  assert_output --partial "baseline-apps install components=comp-gui dry=0"
  assert_output --partial "baseline-desktop install components=comp-gnome dry=0"
  assert_output --partial "meta-ai-dev install dry=0"
}

@test "an already-cloned repo is left untouched (no re-clone, no git pull)" {
  seed_fixture_repos
  echo "marker: pre-existing dev tree" > "$CODE_ROOT_DIR/baseline-shell/DIRTY_MARKER"
  mock_git_clone_from_fixtures   # would overwrite if (wrongly) invoked for baseline-shell

  run bash "$SCRIPT" --selection golden --yes --dry-run
  assert_success
  [ -f "$CODE_ROOT_DIR/baseline-shell/DIRTY_MARKER" ]
}

@test "--dry-run on a completely fresh, uncloned box just prints the plan — no clone attempted" {
  # Deliberately NOT seed_fixture_repos / mock_git here: $CODE_ROOT_DIR is empty. --selection
  # --dry-run must work on this — the whole point is a preview before anything is cloned.
  run bash "$SCRIPT" --selection golden --yes --dry-run
  assert_success
  assert_output --partial "Apply plan for --selection golden"
  assert_output --partial "baseline-shell|comp-a,comp-b"
  assert_output --partial "baseline-apps|comp-gui"
  assert_output --partial "baseline-desktop|comp-gnome"
  assert_output --partial "meta-ai-dev|1"
  # Nothing was cloned and no selected.toml was written — genuinely "touch nothing".
  [ ! -d "$CODE_ROOT_DIR/baseline-shell" ]
  [ ! -f "$BASELINE_SETUP_SELECTED_FILE" ]
}

@test "--dry-run twice against the same profile produces an identical plan (no gum, no TTY)" {
  # The Phase 6 "Done when" acceptance line, read literally: the same selection replayed via
  # --selection … --yes must produce an identical apply plan — checked here as apply_plan()'s own
  # ordered repo|components output, byte for byte, across two independent invocations.
  run bash "$SCRIPT" --selection golden --yes --dry-run
  assert_success
  local plan1="$output"

  run bash "$SCRIPT" --selection golden --yes --dry-run
  assert_success
  local plan2="$output"

  [ "$plan1" = "$plan2" ]
}

@test "empty-selection layer is skipped, not defaulted (real apply, fixtures pre-cloned)" {
  seed_fixture_repos
  unset BASELINE_SHELL_PLATFORM_SH
  local sel="$BATS_TEST_TMPDIR/empty-apps.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a"]

[baseline-apps]
components = []

[meta-ai-dev]
enabled = true
EOF
  export BASELINE_SETUP_PROFILES_DIR="$BATS_TEST_TMPDIR/profiles"
  mkdir -p "$BASELINE_SETUP_PROFILES_DIR"
  cp "$sel" "$BASELINE_SETUP_PROFILES_DIR/empty-apps.toml"

  run bash "$SCRIPT" --selection empty-apps --yes
  assert_success
  assert_output --partial "skip: baseline-apps (empty selection"

  run cat "$STUB_LOG"
  refute_output --partial "baseline-apps"
  assert_output --partial "baseline-shell install components=comp-a dry=0"
}

@test "headless auto-hide: gui-requiring components are dropped, others still apply (real apply)" {
  seed_fixture_repos
  export FIXTURE_PLATFORM_GUI=0
  export FIXTURE_PLATFORM_DE=none
  unset BASELINE_SHELL_PLATFORM_SH

  run bash "$SCRIPT" --selection golden --yes
  assert_success
  assert_output --partial "skip: comp-gui — not applicable on this platform"
  assert_output --partial "skip: comp-gnome — not applicable on this platform"

  run cat "$STUB_LOG"
  assert_output --partial "baseline-shell install components=comp-a,comp-b dry=0"
  assert_output --partial "baseline-apps install components= dry=0"
  assert_output --partial "baseline-desktop install components= dry=0"
}

@test "one layer's install failure doesn't abort the batch, and the run exits non-zero (real apply)" {
  seed_fixture_repos
  unset BASELINE_SHELL_PLATFORM_SH
  export STUB_FAIL_REPO=baseline-apps

  run bash "$SCRIPT" --selection golden --yes
  assert_failure

  run cat "$STUB_LOG"
  assert_output --partial "baseline-shell install"
  assert_output --partial "baseline-desktop install"
  assert_output --partial "meta-ai-dev install"
}

@test "--selection applied twice produces the same selected.toml (idempotent copy)" {
  seed_fixture_repos
  unset BASELINE_SHELL_PLATFORM_SH

  run bash "$SCRIPT" --selection golden --yes
  assert_success
  cp "$BASELINE_SETUP_SELECTED_FILE" "$BATS_TEST_TMPDIR/selected-run1.toml"

  run bash "$SCRIPT" --selection golden --yes
  assert_success
  cp "$BASELINE_SETUP_SELECTED_FILE" "$BATS_TEST_TMPDIR/selected-run2.toml"

  diff "$BATS_TEST_TMPDIR/selected-run1.toml" "$BATS_TEST_TMPDIR/selected-run2.toml"
}

@test "an unknown component id in a profile fails clearly, not as a silent platform-skip" {
  seed_fixture_repos
  unset BASELINE_SHELL_PLATFORM_SH
  local sel="$BATS_TEST_TMPDIR/typo.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a-typo"]
EOF
  export BASELINE_SETUP_PROFILES_DIR="$BATS_TEST_TMPDIR/profiles"
  mkdir -p "$BASELINE_SETUP_PROFILES_DIR"
  cp "$sel" "$BASELINE_SETUP_PROFILES_DIR/typo.toml"

  run bash "$SCRIPT" --selection typo --yes
  assert_failure
  assert_output --partial "unknown component id: 'comp-a-typo'"
  refute_output --partial "not applicable on this platform"
}

@test "a component id never appears in baseline-setup.sh or lib/ (invariant 2)" {
  run bash -c "grep -rEo 'comp-[a-z]+' '$SCRIPT' '$TESTS_DIR/../lib' || true"
  assert_output ""
}
