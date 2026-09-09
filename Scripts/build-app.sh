#!/usr/bin/env bash
# Builds Daisy.app into dist/. Usage: Scripts/build-app.sh [version] [--universal]
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

APP="dist/Daisy.app"
mkdir -p dist
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" -eq 1 ]; then
  echo "==> Building release binary (universal)"
  swift build -c release --scratch-path .build/arm64 -Xswiftc -target -Xswiftc arm64-apple-macos14.0
  swift build -c release --scratch-path .build/x86_64 -Xswiftc -target -Xswiftc x86_64-apple-macos14.0
  lipo -create -output "$APP/Contents/MacOS/Daisy" \
    .build/arm64/release/Daisy .build/x86_64/release/Daisy
  lipo -archs "$APP/Contents/MacOS/Daisy"
else
  ARCH="$(uname -m)"
  echo "==> Building release binary ($ARCH)"
  swift build -c release --scratch-path .build/rel -Xswiftc -target -Xswiftc "${ARCH}-apple-macos14.0"
  cp ".build/rel/release/Daisy" "$APP/Contents/MacOS/Daisy"
fi

echo "==> Assembling bundle"
if [ ! -f Resources/Daisy.icns ]; then
  echo "==> Generating icon"
  swift Scripts/makeicon.swift Resources >/dev/null
  iconutil -c icns Resources/Daisy.iconset -o Resources/Daisy.icns
fi
cp Resources/Daisy.icns "$APP/Contents/Resources/Daisy.icns"
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
