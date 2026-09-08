#!/usr/bin/env bash
# Builds Kuori.app into dist/. Usage: Scripts/build-app.sh [version] [--universal]
#
# Default: a single-arch build for this Mac. --universal builds arm64 + x86_64
# and stitches them with lipo (there is no multi-arch SwiftPM build without
# Xcode). Bundled engines under Resources/engine/ are copied in and each nested
# Mach-O is signed before the outer bundle, or the app won't launch on Apple
# Silicon.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.3.0"
UNIVERSAL=0
for a in "$@"; do
  case "$a" in
    --universal) UNIVERSAL=1 ;;
    *) VERSION="$a" ;;
  esac
done

APP="dist/Kuori.app"
mkdir -p dist
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" -eq 1 ]; then
  echo "==> Building release binary (universal)"
  swift build -c release --scratch-path .build/arm64 -Xswiftc -target -Xswiftc arm64-apple-macos14.0
  swift build -c release --scratch-path .build/x86_64 -Xswiftc -target -Xswiftc x86_64-apple-macos14.0
  lipo -create -output "$APP/Contents/MacOS/Kuori" \
    .build/arm64/release/Kuori .build/x86_64/release/Kuori
  lipo -archs "$APP/Contents/MacOS/Kuori"
else
  ARCH="$(uname -m)"
  echo "==> Building release binary ($ARCH)"
  swift build -c release --scratch-path .build/rel -Xswiftc -target -Xswiftc "${ARCH}-apple-macos14.0"
  cp ".build/rel/release/Kuori" "$APP/Contents/MacOS/Kuori"
fi

echo "==> Assembling bundle"
if [ ! -f Resources/Kuori.icns ]; then
  echo "==> Generating icon"
  swift Scripts/makeicon.swift Resources >/dev/null
  iconutil -c icns Resources/Kuori.iconset -o Resources/Kuori.icns
fi
cp Resources/Kuori.icns "$APP/Contents/Resources/Kuori.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [ -d Resources/engine ]; then
  echo "==> Copying bundled engines"
  cp -R Resources/engine "$APP/Contents/Resources/engine"
  find "$APP/Contents/Resources/engine" -type f \( -perm -u+x -o -name '*.dylib' \) -print0 \
    | while IFS= read -r -d '' f; do codesign --force --sign - "$f" 2>/dev/null || true; done
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature ok"
echo "==> Built $APP ($VERSION)"
