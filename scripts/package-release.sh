#!/bin/bash
# Build the app, then write dist/HiDPI-<version>.zip, dist/HiDPI-<version>.dmg, and dist/appcast.xml.
# Sparkle EdDSA signing runs only when SPARKLE_ED_PRIVATE_KEY is set and Config/SUPublicEDKey is real.
# Usage: scripts/package-release.sh 1.2.3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
cd "$ROOT"

VERSION="${1:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/package-release.sh 1.2.3" >&2
  exit 1
fi
validate_version "$VERSION"

"$ROOT/scripts/build-app.sh" "$VERSION"

APP="$ROOT/dist/HiDPI.app"
ZIP="$ROOT/dist/HiDPI-${VERSION}.zip"
DMG="$ROOT/dist/HiDPI-${VERSION}.dmg"
mkdir -p "$ROOT/dist"

make_zip() {
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
}

make_dmg() {
  local stage
  stage="$(mktemp -d)"
  rm -f "$DMG"
  cp -R "$APP" "$stage/HiDPI.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "HiDPI" -srcfolder "$stage" -ov -format UDZO "$DMG"
  rm -rf "$stage"
}

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
    echo "Notarization secrets are set but APPLE_CERTIFICATE_BASE64 is missing; not submitting." >&2
  else
    echo "Submitting an archive to notarytool."
    TMP_ZIP="$(mktemp -d)/HiDPI.zip"
    ditto -c -k --keepParent "$APP" "$TMP_ZIP"
    xcrun notarytool submit "$TMP_ZIP" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    xcrun stapler staple "$APP"
    rm -rf "$(dirname "$TMP_ZIP")"
  fi
else
  echo "Notarization secrets absent; publishing the signed or ad-hoc app without a ticket."
fi

make_zip
make_dmg

LENGTH="$(stat -f%z "$ZIP")"
SIG_FILE="$(mktemp)"
: > "$SIG_FILE"

PUB="$(tr -d '[:space:]' < "$ROOT/Config/SUPublicEDKey")"
if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_ED_PRIVATE_KEY is not set. appcast.xml will not contain sparkle:edSignature."
elif [[ -z "$PUB" || "$PUB" == PLACEHOLDER* ]]; then
  echo "Config/SUPublicEDKey is still a placeholder. Skipping appcast signing."
  echo "Commit the public key from generate_keys before signing updates."
else
  TOOL=""
  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      TOOL="$candidate"
      break
    fi
  done < <(find .build -type f -name sign_update ! -path '*dSYM*')
  if [[ -z "$TOOL" ]]; then
    echo "sign_update was not found under .build." >&2
    exit 1
  fi
  KEY_FILE="$(mktemp)"
  chmod 600 "$KEY_FILE"
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
  RAW=""
  set +e
  RAW="$("$TOOL" --ed-key-file "$KEY_FILE" -p "$ZIP" 2>/dev/null)"
  sign_status=$?
  if [[ "$sign_status" -ne 0 || -z "$RAW" ]]; then
    RAW="$("$TOOL" --ed-key-file "$KEY_FILE" "$ZIP" 2>/dev/null)"
    sign_status=$?
  fi
  set -e
  rm -f "$KEY_FILE"
  if [[ "$sign_status" -ne 0 || -z "$RAW" ]]; then
    echo "sign_update failed." >&2
    exit 1
  fi
  if [[ "$RAW" == *edSignature=* ]]; then
    printf '%s' "$RAW" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' > "$SIG_FILE"
  else
    printf '%s' "$RAW" | tr -d '[:space:]' > "$SIG_FILE"
  fi
  if [[ ! -s "$SIG_FILE" ]]; then
    echo "sign_update returned an empty signature." >&2
    exit 1
  fi
  echo "Signed ${ZIP} for Sparkle."
fi

APPCAST=""
while IFS= read -r candidate; do
  APPCAST="$candidate"
  break
done < <(find .build -type f -name hidpi-appcast ! -path '*dSYM*')
if [[ -z "$APPCAST" ]]; then
  echo "hidpi-appcast is missing." >&2
  exit 1
fi

NOTES="<p>HiDPI ${VERSION}</p><p><a href=\"https://github.com/$(repo_slug)/releases/tag/v${VERSION}\">发布说明</a></p>"
ARGS=(
  --version "$VERSION"
  --feed-url "$(feed_url)"
  --enclosure-url "$(enclosure_url "$VERSION")"
  --length "$LENGTH"
  --output "$ROOT/dist/appcast.xml"
  --title "HiDPI ${VERSION}"
  --notes "$NOTES"
)
if [[ -s "$SIG_FILE" ]]; then
  ARGS+=(--signature "$(cat "$SIG_FILE")")
fi
rm -f "$SIG_FILE"
"$APPCAST" "${ARGS[@]}"

if ! grep -q "<sparkle:version>${VERSION}</sparkle:version>" "$ROOT/dist/appcast.xml"; then
  echo "appcast.xml is missing sparkle:version ${VERSION}." >&2
  exit 1
fi
echo "Packaged:"
echo "  ${ZIP}"
echo "  ${DMG}"
echo "  ${ROOT}/dist/appcast.xml"
