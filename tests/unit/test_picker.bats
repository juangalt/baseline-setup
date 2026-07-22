#!/usr/bin/env bats
# Unit tests for lib/picker.sh's pure helpers. The gum-facing functions (picker_layer, run_picker)
# need a real TTY + gum binary and aren't exercised here — see the file's own header comment.

load '../helpers/common.bash'

setup() {
  isolate_environment
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/picker.sh"
}

@test "csv_to_toml_array: empty csv -> empty string" {
  run csv_to_toml_array ""
  assert_success
  assert_output ""
}

@test "csv_to_toml_array: single id" {
  run csv_to_toml_array "comp-a"
  assert_success
  assert_output '"comp-a"'
}

@test "csv_to_toml_array: multiple ids, comma+space separated, quoted" {
  run csv_to_toml_array "comp-a,comp-b"
  assert_success
  assert_output '"comp-a", "comp-b"'
}
