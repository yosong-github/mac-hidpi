#!/bin/bash
# Build dist/HiDPI.app. Version becomes CFBundleShortVersionString and CFBundleVersion.
# Usage: scripts/build-app.sh 1.2.3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
cd "$ROOT"

VERSION="${1:-${VERSION:-0.0.0}}"
validate_version "$VERSION"

echo "Swift:"
swift --version
echo "Building HiDPI ${VERSION}"

build_slices() {
  echo "Building arm64 and x86_64 slices"
  swift build -c release --triple arm64-apple-macosx13.0
  swift build -c release --triple x86_64-apple-macosx13.0
}

set +e
swift build -c release --arch arm64 --arch x86_64
universal_status=$?
set -e
if [[ "$universal_status" -ne 0 ]]; then
  echo "swift build --arch arm64 --arch x86_64 failed; building each triple."
  build_slices
fi

echo "Release binaries:"
find .build -type f \( -name HiDPI -o -name hidpi-appcast \) ! -path '*.dSYM*' -print

pick_binary() {
  local name="$1"
  local candidate info
  candidate=""
  while IFS= read -r candidate; do
    if is_universal "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(find .build -type f -name "$name" ! -path '*.dSYM*' ! -path '*dSYM*')
  local arm="" x86=""
  while IFS= read -r candidate; do
    info="$(lipo -archs "$candidate" 2>/dev/null || true)"
    if [[ "$info" == *arm64* && "$info" != *x86_64* ]]; then
      arm="$candidate"
    elif [[ "$info" == *x86_64* && "$info" != *arm64* ]]; then
      x86="$candidate"
    fi
  done < <(find .build -type f -name "$name" ! -path '*.dSYM*' ! -path '*dSYM*')
  if [[ -z "$arm" || -z "$x86" ]]; then
    echo "Could not find both arm64 and x86_64 ${name} binaries (arm='${arm}' x86='${x86}')." >&2
    return 1
  fi
  local lipo_out
  lipo_out="$(mktemp)"
  lipo -create "$arm" "$x86" -output "$lipo_out"
  printf '%s' "$lipo_out"
}

if ! BIN="$(pick_binary HiDPI)"; then
  echo "Universal product missing after the first build; compiling each triple."
  build_slices
  BIN="$(pick_binary HiDPI)"
fi
if ! is_universal "$BIN"; then
  echo "HiDPI binary is not universal: $(lipo -info "$BIN")" >&2
  exit 1
fi
echo "Using $(lipo -info "$BIN")"

APPCAST_BIN=""
while IFS= read -r candidate; do
  APPCAST_BIN="$candidate"
  break
done < <(find .build -type f -name hidpi-appcast ! -path '*dSYM*')
if [[ -z "$APPCAST_BIN" ]]; then
  swift build -c release --product hidpi-appcast
  while IFS= read -r candidate; do
    APPCAST_BIN="$candidate"
    break
  done < <(find .build -type f -name hidpi-appcast ! -path '*dSYM*')
fi
if [[ -z "$APPCAST_BIN" ]]; then
  echo "hidpi-appcast was not built." >&2
  exit 1
fi

FRAMEWORK=""
while IFS= read -r candidate; do
  mach=""
  while IFS= read -r nested; do
    if [[ "$(basename "$nested")" == "Sparkle" ]] && is_universal "$nested"; then
      mach="$nested"
      break
    fi
  done < <(find "$candidate" -type f -name Sparkle ! -path '*dSYM*')
  if [[ -n "$mach" ]]; then
    FRAMEWORK="$candidate"
    break
  fi
  if [[ -z "$FRAMEWORK" ]]; then
    FRAMEWORK="$candidate"
  fi
done < <(find .build -type d -name Sparkle.framework)
if [[ -z "$FRAMEWORK" ]]; then
  echo "Sparkle.framework was not produced by the build." >&2
  exit 1
fi
echo "Sparkle.framework: ${FRAMEWORK}"

APP="$ROOT/dist/HiDPI.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HiDPI"
chmod 755 "$APP/Contents/MacOS/HiDPI"
cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
printf 'APPL????' > "$APP/Contents/PkgInfo"

FEED="$(feed_url)"
PUB="$(tr -d '[:space:]' < "$ROOT/Config/SUPublicEDKey")"
sed \
  -e "s/__VERSION__/${VERSION}/g" \
  -e "s|__FEED_URL__|${FEED}|g" \
  -e "s|__PUBLIC_KEY__|${PUB}|g" \
  "$ROOT/Config/Info.plist.template" > "$APP/Contents/Info.plist"
if [[ -z "$PUB" || "$PUB" == PLACEHOLDER* ]]; then
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP/Contents/Info.plist"
  echo "SUPublicEDKey left unset (Config/SUPublicEDKey is still a placeholder)."
fi
plutil -lint "$APP/Contents/Info.plist"

ICON_SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICON_SET"
PNG="$ROOT/Resources/AppIcon-1024.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PNG" --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$PNG" --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o "$APP/Contents/Resources/AppIcon.icns"

LINKED="$(otool -L "$APP/Contents/MacOS/HiDPI")"
if [[ "$LINKED" != *'@rpath/Sparkle.framework'* ]]; then
  echo "HiDPI is not linked against Sparkle:" >&2
  printf '%s\n' "$LINKED" >&2
  exit 1
fi
LOAD_CMDS="$(otool -l "$APP/Contents/MacOS/HiDPI")"
if [[ "$LOAD_CMDS" != *'@executable_path/../Frameworks'* ]]; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/HiDPI"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ -n "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
  if [[ -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]]; then
    echo "APPLE_CERTIFICATE_BASE64 is set but APPLE_CERTIFICATE_PASSWORD is empty." >&2
    exit 1
  fi
  KEYCHAIN="${RUNNER_TEMP:-/tmp}/hidpi-signing.keychain-db"
  KEYCHAIN_PASS="$(uuidgen)"
  B64_FILE="$(mktemp)"
  P12_FILE="$(mktemp)"
  printf '%s' "$APPLE_CERTIFICATE_BASE64" > "$B64_FILE"
  if ! base64 -D -i "$B64_FILE" -o "$P12_FILE"; then
    base64 --decode -i "$B64_FILE" -o "$P12_FILE"
  fi
  rm -f "$B64_FILE"
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security import "$P12_FILE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  rm -f "$P12_FILE"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN"
  security list-keychains -d user -s "$KEYCHAIN" "$(security list-keychains -d user | sed -e 's/"//g')"
  security default-keychain -s "$KEYCHAIN"
  SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "Imported the p12 but found no codesigning identity." >&2
    exit 1
  fi
  echo "Signing with identity: ${SIGN_IDENTITY}"
else
  echo "No APPLE_CERTIFICATE_BASE64 secret; ad-hoc signing."
fi

sign_item() {
  local target="$1"
  shift
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$@" "$target"
  else
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$@" "$target"
  fi
}

if [[ -d "$APP/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' bin; do
    file_info="$(file "$bin")"
    if [[ "$file_info" == *Mach-O* ]]; then
      sign_item "$bin" --preserve-metadata=entitlements || sign_item "$bin"
    fi
  done < <(find "$APP/Contents/Frameworks" -type f -print0)
  while IFS= read -r -d '' bundle; do
    sign_item "$bundle" --preserve-metadata=entitlements || sign_item "$bundle"
  done < <(find "$APP/Contents/Frameworks" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' -o -name '*.bundle' \) -print0)
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --entitlements "$ROOT/Config/HiDPI.entitlements" "$APP"
fi
codesign --verify --verbose=2 "$APP"
echo "Signed $(basename "$APP") as ${SIGN_IDENTITY}"

SHORT="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")"
UI="$(plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist")"
BAKED_FEED="$(plutil -extract SUFeedURL raw -o - "$APP/Contents/Info.plist")"
if [[ "$SHORT" != "$VERSION" || "$BUILD" != "$VERSION" ]]; then
  echo "Version mismatch: short=${SHORT} build=${BUILD} expected=${VERSION}" >&2
  exit 1
fi
if [[ "$UI" != "true" ]]; then
  echo "LSUIElement is not true." >&2
  exit 1
fi
if [[ "$BAKED_FEED" != "$FEED" ]]; then
  echo "SUFeedURL mismatch: ${BAKED_FEED} != ${FEED}" >&2
  exit 1
fi
echo "Built ${APP} (${VERSION})"
