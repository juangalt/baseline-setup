#!/usr/bin/env bash
#
# lib/gum-bootstrap.sh — checksum-verified fetch of the `gum` TUI binary (charmbracelet/gum),
# used only by the interactive picker (lib/picker.sh). Never invoked on the --selection path (C5
# runtime step 5: "Skipped entirely when --selection is given").
#
# Version + per-asset sha256 are pinned below, both lifted together from upstream's own
# checksums.txt (https://github.com/charmbracelet/gum/releases/download/v<ver>/checksums.txt) at
# the time this was written. Bump both together, never the version alone — an unpinned checksum
# defeats the point of verifying one.

GUM_VERSION="${BASELINE_SETUP_GUM_VERSION:-0.17.0}"
GUM_BASE_URL="${BASELINE_SETUP_GUM_BASE_URL:-https://github.com/charmbracelet/gum/releases/download}"
GUM_CACHE_DIR="${BASELINE_SETUP_GUM_CACHE_DIR:-$HOME/.cache/baseline-setup/gum}"

# sha256 for every (os,arch) asset this function might select, pinned to GUM_VERSION. Only the
# fleet's real targets (Linux x86_64/arm64 — see platform.sh's PLATFORM_FAMILY roster, there is
# no macOS family) are covered; anything else degrades to the error path below.
_gum_asset_name() {  # -> filename, empty if unsupported
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  [ "$os" = "Linux" ] || { printf ''; return; }
  case "$arch" in
    x86_64)          printf 'gum_%s_Linux_x86_64.tar.gz' "$GUM_VERSION" ;;
    aarch64|arm64)   printf 'gum_%s_Linux_arm64.tar.gz' "$GUM_VERSION" ;;
    *)                printf '' ;;
  esac
}

_gum_checksum() {  # asset-filename -> sha256, empty if not pinned
  case "$1" in
    "gum_${GUM_VERSION}_Linux_x86_64.tar.gz")
      [ "$GUM_VERSION" = 0.17.0 ] && printf '69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb' ;;
    "gum_${GUM_VERSION}_Linux_arm64.tar.gz")
      [ "$GUM_VERSION" = 0.17.0 ] && printf 'b0b9ed95cbf7c8b7073f17b9591811f5c001e33c7cfd066ca83ce8a07c576f9c' ;;
  esac
}

# Prints the path to a verified `gum` binary on success. On any failure — unsupported
# OS/arch, download failure, checksum mismatch — prints nothing and returns non-zero; the
# caller (baseline-setup.sh's interactive path) is responsible for the hard-error message naming
# the `--selection <name> --yes` escape hatch (C5 step 5).
gum_bootstrap() {
  command -v gum >/dev/null 2>&1 && { command -v gum; return 0; }

  local cached="$GUM_CACHE_DIR/$GUM_VERSION/gum"
  [ -x "$cached" ] && { printf '%s' "$cached"; return 0; }

  local asset; asset="$(_gum_asset_name)"
  if [ -z "$asset" ]; then
    echo "ERROR: gum has no pinned build for $(uname -s)/$(uname -m)" >&2
    return 1
  fi
  local want_sha; want_sha="$(_gum_checksum "$asset")"
  if [ -z "$want_sha" ]; then
    echo "ERROR: no pinned checksum for $asset (GUM_VERSION=$GUM_VERSION) — refusing to fetch unverified" >&2
    return 1
  fi

  local tmp; tmp="$(mktemp -d)" || return 1
  # $tmp is expanded now, deliberately, not at trap-fire time.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  if ! curl -fsSL -o "$tmp/$asset" "$GUM_BASE_URL/v$GUM_VERSION/$asset"; then
    echo "ERROR: failed to download $asset from $GUM_BASE_URL/v$GUM_VERSION/" >&2
    return 1
  fi

  local got_sha
  got_sha="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
  if [ "$got_sha" != "$want_sha" ]; then
    echo "ERROR: checksum mismatch for $asset (expected $want_sha, got $got_sha) — refusing to use it" >&2
    return 1
  fi

  tar -xzf "$tmp/$asset" -C "$tmp" || { echo "ERROR: failed to extract $asset" >&2; return 1; }
  local extracted
  extracted="$(find "$tmp" -maxdepth 2 -type f -name gum | head -n1)"
  if [ -z "$extracted" ]; then
    echo "ERROR: gum binary not found inside $asset after extraction" >&2
    return 1
  fi

  mkdir -p "$(dirname "$cached")"
  cp "$extracted" "$cached"
  chmod +x "$cached"
  printf '%s' "$cached"
}
