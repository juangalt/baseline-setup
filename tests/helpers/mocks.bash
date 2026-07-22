#!/usr/bin/env bash
# Mock factory helpers. Requires setup_mock_bin() to have been called first.

setup_mock_bin() {
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}

# A fake `git` that intercepts `clone <url> <dest>`: materializes the matching fixture repo dir
# (tests/fixtures/repos/<name>, matched by the URL's basename minus .git) at dest instead of a
# real network clone. Anything else is a no-op success — baseline-setup.sh only ever calls `git
# clone`. This is the "git mock for the clone step" the Phase 6 plan calls for.
mock_git_clone_from_fixtures() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'FIXTURES_REPOS_DIR=%q\n' "$FIXTURES_DIR/repos"
    printf 'if [ "${1:-}" = "clone" ]; then\n'
    printf '  shift\n'
    printf '  args=()\n'
    printf '  for a in "$@"; do\n'
    printf '    case "$a" in -q|--depth=*) continue ;; esac\n'
    printf '    args+=("$a")\n'
    printf '  done\n'
    printf '  url="${args[0]}"; dest="${args[1]}"\n'
    printf '  name="$(basename "$url" .git)"\n'
    printf '  if [ -d "$FIXTURES_REPOS_DIR/$name" ]; then\n'
    printf '    cp -r "$FIXTURES_REPOS_DIR/$name" "$dest"\n'
    printf '  else\n'
    printf '    mkdir -p "$dest"\n'
    printf '  fi\n'
    printf '  mkdir -p "$dest/.git"\n'
    printf '  exit 0\n'
    printf 'fi\n'
    printf 'exit 0\n'
  } > "$MOCK_BIN/git"
  chmod +x "$MOCK_BIN/git"
}
