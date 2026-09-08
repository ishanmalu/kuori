#!/usr/bin/env bash
# Builds Kuori.app into dist/. Usage: Scripts/build-app.sh [version]
#
# arm64-only for now (this machine + personal use). Universal is a later phase:
# it needs both-arch bottles of every bundled engine lipo'd together.
# Nested engine binaries are signed inside-out before the outer bundle, or the
# app won't launch on Apple Silicon.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="dist/Kuori.app"
ARCH="$(uname -m)"

echo "==> Building release binary ($ARCH)"
swift build -c release --scratch-path .build/rel \
  -Xswiftc -target -Xswiftc "${ARCH}-apple-macos14.0"

mkdir -p dist
echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/rel/release/Kuori" "$APP/Contents/MacOS/Kuori"

if [ ! -f Resources/Kuori.icns ]; then
  echo "==> Generating icon"
  swift Scripts/makeicon.swift Resources >/dev/null
  iconutil -c icns Resources/Kuori.iconset -o Resources/Kuori.icns
fi
cp Resources/Kuori.icns "$APP/Contents/Resources/Kuori.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# Bundled conversion engines (optional — the app also finds Homebrew copies).
if [ -d Resources/engine ]; then
  echo "==> Copying bundled engines"
  cp -R Resources/engine "$APP/Contents/Resources/engine"
  find "$APP/Contents/Resources/engine" -type f \( -perm -u+x -o -name '*.dylib' \) -print0 \
    | while IFS= read -r -d '' f; do codesign --force --sign - "$f" 2>/dev/null || true; done
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature ok"

echo "==> Built $APP ($VERSION, $ARCH)"
