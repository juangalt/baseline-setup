#!/usr/bin/env bats
# Unit tests for lib/gum-bootstrap.sh — the checksum-verified `gum` fetch. Only the failure paths
# and the two short-circuits (already on PATH, already cached) are practical to test without
# network: a "happy path, freshly downloaded" test would need a fixture tarball whose sha256
# matches the real pinned upstream hash, which isn't reproducible from a fixture we author.

bats_require_minimum_version 1.5.0

load '../helpers/common.bash'
load '../helpers/mocks.bash'

setup() {
  isolate_environment
  setup_mock_bin
  export BASELINE_SETUP_GUM_CACHE_DIR="$BATS_TEST_TMPDIR/gum-cache"
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/gum-bootstrap.sh"
}

mock_uname() {  # os arch
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  -s) echo %q ;;\n' "$1"
    printf '  -m) echo %q ;;\n' "$2"
    printf 'esac\n'
  } > "$MOCK_BIN/uname"
  chmod +x "$MOCK_BIN/uname"
}

@test "gum_bootstrap: returns immediately if gum is already on PATH" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exit 0\n'
  } > "$MOCK_BIN/gum"
  chmod +x "$MOCK_BIN/gum"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "curl should not be called" >&2\n'
    printf 'exit 1\n'
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"

  run gum_bootstrap
  assert_success
  assert_output "$MOCK_BIN/gum"
}

@test "gum_bootstrap: returns the cached binary without touching the network" {
  local cached_dir="$BASELINE_SETUP_GUM_CACHE_DIR/0.17.0"
  mkdir -p "$cached_dir"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$cached_dir/gum"
  chmod +x "$cached_dir/gum"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "curl should not be called" >&2\n'
    printf 'exit 1\n'
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"

  run gum_bootstrap
  assert_success
  assert_output "$cached_dir/gum"
}

@test "gum_bootstrap: unsupported OS refuses cleanly, naming the OS/arch" {
  mock_uname Windows x86_64
  run gum_bootstrap
  assert_failure
  assert_output --partial "no pinned build"
}

@test "gum_bootstrap: unsupported arch refuses cleanly" {
  mock_uname Linux riscv64
  run gum_bootstrap
  assert_failure
  assert_output --partial "no pinned build"
}

@test "gum_bootstrap: an unpinned GUM_VERSION refuses without ever calling curl" {
  mock_uname Linux x86_64
  # GUM_VERSION is captured at source time — the env var must be set BEFORE re-sourcing, not
  # after (setup() already sourced it once against the default).
  export BASELINE_SETUP_GUM_VERSION=9.9.9
  # shellcheck disable=SC1090
  source "$TESTS_DIR/../lib/gum-bootstrap.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "curl should not be called for an unpinned version" >&2\n'
    printf 'exit 1\n'
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"

  run gum_bootstrap
  assert_failure
  assert_output --partial "no pinned checksum"
}

@test "gum_bootstrap: a download failure is refused cleanly" {
  mock_uname Linux x86_64
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exit 1\n'
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"

  run gum_bootstrap
  assert_failure
  assert_output --partial "failed to download"
}

@test "gum_bootstrap: a checksum mismatch is refused and nothing is cached" {
  mock_uname Linux x86_64
  {
    printf '#!/usr/bin/env bash\n'
    # Any curl invocation just writes arbitrary bytes to -o's target — real sha256sum will
    # compute a real hash of it, which will not equal the pinned real-upstream hash.
    printf 'while [ $# -gt 0 ]; do\n'
    printf '  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac\n'
    printf 'done\n'
    printf 'printf "not the real gum tarball" > "$out"\n'
  } > "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"

  run gum_bootstrap
  assert_failure
  assert_output --partial "checksum mismatch"
  [ ! -e "$BASELINE_SETUP_GUM_CACHE_DIR/0.17.0/gum" ]
}
