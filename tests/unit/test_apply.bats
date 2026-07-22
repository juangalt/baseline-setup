#!/usr/bin/env bats
# Unit tests for lib/apply.sh — the apply engine, against the fixture repos under
# tests/fixtures/repos/ (stub installers logging to $STUB_LOG, contract C3-shaped).

load '../helpers/common.bash'
load '../helpers/mocks.bash'

setup() {
  isolate_environment
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/manifest.sh"
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/apply.sh"
  seed_fixture_repos
  mock_gui_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
}

@test "LAYER_ROSTER names no component id (invariant 2 sanity check within apply.sh itself)" {
  # A literal grep of apply.sh's source for a real component id would be the anti-pattern
  # ARCHITECTURE.md's "The boundary" warns against — assert the roster is repo:script:invoke
  # triples only (structural, never a component id).
  run bash -c "echo \"\$LAYER_ROSTER\" | grep -Eo 'comp-[a-z]+'"
  assert_failure
}

@test "apply_layer: invokes the flags-style stub (bootstrap.sh) with the visible components" {
  run apply_layer baseline-shell bootstrap.sh flags "comp-a,comp-b" 0
  assert_success
  run cat "$STUB_LOG"
  assert_output --partial "baseline-shell install components=comp-a,comp-b dry=0"
}

@test "apply_layer: invokes the install-subcommand-style stub (baseline-apps.sh) with the visible components" {
  mock_gui_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run apply_layer baseline-apps baseline-apps.sh install "comp-gui" 0
  assert_success
  run cat "$STUB_LOG"
  assert_output --partial "baseline-apps install components=comp-gui dry=0"
}

@test "apply_layer: a flags-style script rejects an install subcommand it never asked for (regression guard)" {
  # This is the exact shape of the real Phase 7 bug: apply_layer used to hardcode "install" for
  # every layer, but bootstrap.sh has no subcommand — it just takes flags. Calling it with
  # invoke=install (wrong) must fail loudly via the stub's strict rejection, proving the "flags"
  # style is genuinely required for baseline-shell, not just cosmetically different.
  run apply_layer baseline-shell bootstrap.sh install "comp-a" 0
  assert_failure
  run cat "$STUB_LOG"
  refute_output --partial "baseline-shell"
}

@test "apply_layer: --dry-run threads through to the installer" {
  run apply_layer baseline-shell bootstrap.sh flags "comp-a" 1
  assert_success
  run cat "$STUB_LOG"
  assert_output --partial "dry=1"
}

@test "apply_layer: filters a gui-requiring component before invoking, when headless" {
  mock_headless_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run apply_layer baseline-apps baseline-apps.sh install "comp-gui" 0
  assert_success
  run cat "$STUB_LOG"
  assert_output --partial "components= dry=0"
}

@test "apply_layer: missing clone reports and returns failure, not a crash" {
  rm -rf "$CODE_ROOT_DIR/baseline-shell"
  run apply_layer baseline-shell bootstrap.sh flags "comp-a" 0
  assert_failure
  assert_output --partial "not cloned"
}

@test "apply_l2: skips when not enabled" {
  run apply_l2 0 0
  assert_success
  assert_output --partial "skip: meta-ai-dev"
  run cat "$STUB_LOG"
  refute_output --partial "meta-ai-dev"
}

@test "apply_l2: runs the bare install.sh when enabled" {
  run apply_l2 1 0
  assert_success
  run cat "$STUB_LOG"
  assert_output --partial "meta-ai-dev install dry=0"
}

@test "apply_selection: fully-deselected layer (empty table) is skipped, not defaulted" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = []

[baseline-apps]
components = ["comp-gui"]

[meta-ai-dev]
enabled = true
EOF
  run apply_selection "$sel" 0
  assert_success
  assert_output --partial "skip: baseline-shell (empty selection"
  run cat "$STUB_LOG"
  refute_output --partial "baseline-shell"
  assert_output --partial "baseline-apps install components=comp-gui"
}

@test "apply_selection: a missing layer table is skipped (ADR 0004 D8), not defaulted" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-apps]
components = ["comp-gui"]
EOF
  run apply_selection "$sel" 0
  assert_success
  assert_output --partial "skip: baseline-shell (no selection table"
  assert_output --partial "skip: baseline-desktop (no selection table"
}

@test "apply_selection: one layer's failure doesn't abort the batch" {
  export STUB_FAIL_REPO=baseline-apps
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a"]

[baseline-apps]
components = ["comp-gui"]

[baseline-desktop]
components = ["comp-gnome"]

[meta-ai-dev]
enabled = true
EOF
  run apply_selection "$sel" 0
  assert_failure   # overall run reports failure...
  run cat "$STUB_LOG"
  # ...but every OTHER layer still ran, including the ones after the failing one.
  assert_output --partial "baseline-shell install"
  assert_output --partial "baseline-desktop install"
  assert_output --partial "meta-ai-dev install"
}

@test "apply_plan: prints the ordered repo|csv plan, including a skip marker for absent tables" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a", "comp-b"]

[meta-ai-dev]
enabled = true
EOF
  run apply_plan "$sel"
  assert_success
  assert_line "baseline-shell|comp-a,comp-b"
  assert_line "baseline-apps|<skip: no table>"
  assert_line "baseline-desktop|<skip: no table>"
  assert_line "meta-ai-dev|1"
}

@test "apply_plan: identical for two selection files with the same content (copy fidelity)" {
  local a="$BATS_TEST_TMPDIR/a.toml" b="$BATS_TEST_TMPDIR/b.toml"
  cp "$FIXTURES_DIR/profiles/golden.toml" "$a"
  cp "$a" "$b"
  run apply_plan "$a"
  local plan_a="$output"
  run apply_plan "$b"
  local plan_b="$output"
  [ "$plan_a" = "$plan_b" ]
}
