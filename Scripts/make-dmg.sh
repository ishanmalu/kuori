#!/usr/bin/env bash
# Packages dist/Daisy.app into dist/Daisy-<version>.dmg.
# Usage: Scripts/make-dmg.sh [version]   (build the .app first)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.3.0}"
APP="dist/Daisy.app"
[ -d "$APP" ] || { echo "build dist/Daisy.app first (Scripts/build-app.sh)"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/Daisy-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Daisy $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "==> $DMG"
