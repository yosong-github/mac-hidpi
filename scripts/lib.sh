#!/bin/bash
# Shared helpers for build and release scripts. Source this file; do not execute it.

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be MAJOR.MINOR.PATCH (got '${version}')." >&2
    return 1
  fi
  local major minor patch part
  IFS=. read -r major minor patch <<<"$version"
  for part in "$major" "$minor" "$patch"; do
    if [[ ${#part} -gt 1 && "$part" == 0* ]]; then
      echo "Version components cannot have leading zeros (got '${version}')." >&2
      return 1
    fi
  done
}

repo_slug() {
  printf '%s' "${GITHUB_REPOSITORY:-yosong-github/mac-hidpi}"
}

feed_url() {
  if [[ -n "${HIDPI_FEED_URL:-}" ]]; then
    printf '%s' "$HIDPI_FEED_URL"
    return
  fi
  printf '%s' "https://github.com/$(repo_slug)/releases/latest/download/appcast.xml"
}

enclosure_url() {
  local version="$1"
  if [[ -n "${HIDPI_ENCLOSURE_URL:-}" ]]; then
    printf '%s' "$HIDPI_ENCLOSURE_URL"
    return
  fi
  printf '%s' "https://github.com/$(repo_slug)/releases/download/v${version}/HiDPI-${version}.zip"
}

# lipo -archs prints only architecture names, so a path that contains "arm64" cannot fool the check.
is_universal() {
  local archs
  archs="$(lipo -archs "$1" 2>/dev/null || true)"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]
}
