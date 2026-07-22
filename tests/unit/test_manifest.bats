#!/usr/bin/env bats
# Unit tests for lib/manifest.sh — pure TOML-reading/filtering logic, no subprocess needed.

bats_require_minimum_version 1.5.0

load '../helpers/common.bash'

setup() {
  isolate_environment
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/manifest.sh"
  FIX="$FIXTURES_DIR/repos"
}

@test "read_default_components: returns only default=true ids" {
  run read_default_components "$FIX/baseline-shell/manifest.toml"
  assert_success
  assert_output "comp-a"
}

@test "valid_component_ids: lists every id regardless of default" {
  run valid_component_ids "$FIX/baseline-shell/manifest.toml"
  assert_success
  assert_output "comp-a,comp-b"
}

@test "manifest_query: missing file reports an error, not a traceback" {
  run valid_component_ids "$BATS_TEST_TMPDIR/no-such-manifest.toml"
  assert_failure
  assert_output --partial "ERROR"
}

@test "validate_components: unknown id fails listing valid ids" {
  run validate_components "$FIX/baseline-shell/manifest.toml" "comp-a,bogus"
  assert_failure
  assert_output --partial "unknown component id: 'bogus'"
  assert_output --partial "comp-a,comp-b"
}

@test "validate_components: empty csv is a no-op success" {
  run validate_components "$FIX/baseline-shell/manifest.toml" ""
  assert_success
}

@test "validate_components: every id valid succeeds" {
  run validate_components "$FIX/baseline-shell/manifest.toml" "comp-a,comp-b"
  assert_success
}

@test "visible_component_ids: gui=true component hidden when headless" {
  mock_headless_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run visible_component_ids "$FIX/baseline-apps/manifest.toml"
  assert_success
  assert_output ""
}

@test "visible_component_ids: gui=true component visible under a GUI platform" {
  mock_gui_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run visible_component_ids "$FIX/baseline-apps/manifest.toml"
  assert_success
  assert_output "comp-gui"
}

@test "visible_component_ids: de=[gnome] predicate hides on a non-GNOME GUI platform" {
  mock_gui_platform kde
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run visible_component_ids "$FIX/baseline-desktop/manifest.toml"
  assert_success
  assert_output ""
}

@test "visible_component_ids: de=[gnome] predicate visible under GNOME" {
  mock_gui_platform gnome
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run visible_component_ids "$FIX/baseline-desktop/manifest.toml"
  assert_success
  assert_output "comp-gnome"
}

@test "visible_component_ids: requires.de as a bare string (not a list) hides the component and warns, instead of substring-matching" {
  local manifest="$BATS_TEST_TMPDIR/bad-de.toml"
  cat > "$manifest" <<'EOF'
[[component]]
id = "comp-bad-de"
label = "Bad de type"
default = true
requires = { gui = true, de = "gnome" }
EOF
  mock_gui_platform gnome
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run --separate-stderr visible_component_ids "$manifest"
  assert_success
  assert_output ""
  [[ "$stderr" == *"requires.de must be a list"* ]]
}

@test "visible_component_ids: requires.family as a bare string hides the component and warns" {
  local manifest="$BATS_TEST_TMPDIR/bad-family.toml"
  cat > "$manifest" <<'EOF'
[[component]]
id = "comp-bad-family"
label = "Bad family type"
default = true
requires = { family = "debian" }
EOF
  mock_gui_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run --separate-stderr visible_component_ids "$manifest"
  assert_success
  assert_output ""
  [[ "$stderr" == *"requires.family must be a list"* ]]
}

@test "filter_visible: drops hidden ids and reports them, keeps visible ones" {
  mock_headless_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run --separate-stderr filter_visible "$FIX/baseline-apps/manifest.toml" "comp-gui"
  assert_success
  assert_output ""
  assert [ -n "$stderr" ]
  [[ "$stderr" == *"skip: comp-gui"* ]]
}

@test "filter_visible: keeps a requires-less id under any platform" {
  mock_headless_platform
  export PLATFORM_GUI PLATFORM_FAMILY PLATFORM_PKG PLATFORM_ATOMIC PLATFORM_DE
  run filter_visible "$FIX/baseline-shell/manifest.toml" "comp-a,comp-b"
  assert_success
  assert_output "comp-a,comp-b"
}

@test "resolve_needs: transitively adds a needed id not already selected" {
  run resolve_needs "$FIX/baseline-shell/manifest.toml" "comp-b"
  assert_success
  assert_output "comp-a,comp-b"
}

@test "resolve_needs: no-op when the need is already present" {
  run resolve_needs "$FIX/baseline-shell/manifest.toml" "comp-a,comp-b"
  assert_success
  assert_output "comp-a,comp-b"
}

@test "detect_conflicts: reports nothing when the fixture manifest has no conflicts field" {
  run detect_conflicts "$FIX/baseline-shell/manifest.toml" "comp-a,comp-b"
  assert_success
  assert_output ""
}

@test "selection_has_layer: true for a present table, false for an absent one" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a"]
EOF
  run selection_has_layer "$sel" "baseline-shell"
  assert_success
  run selection_has_layer "$sel" "baseline-apps"
  assert_failure
}

@test "selection_components: reads the layer's components array as csv" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[baseline-shell]
components = ["comp-a", "comp-b"]
EOF
  run selection_components "$sel" "baseline-shell"
  assert_success
  assert_output "comp-a,comp-b"
}

@test "selection_components: empty when the file doesn't exist yet" {
  run selection_components "$BATS_TEST_TMPDIR/nope.toml" "baseline-shell"
  assert_success
  assert_output ""
}

@test "selection_l2_enabled: reads enabled=false explicitly" {
  local sel="$BATS_TEST_TMPDIR/sel.toml"
  cat > "$sel" <<'EOF'
[meta-ai-dev]
enabled = false
EOF
  run selection_l2_enabled "$sel"
  assert_success
  assert_output "0"
}

@test "selection_l2_enabled: absent file defaults to disabled (ADR 0004 D8 — missing table = skip)" {
  run selection_l2_enabled "$BATS_TEST_TMPDIR/nope.toml"
  assert_success
  assert_output "0"
}
