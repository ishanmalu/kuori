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

# The in-app updater refuses any download it cannot check against a published
# checksum, so the sums file ships with the release or updating simply stops
# working. Written in the same format shasum reads back.
SUMS="dist/SHA256SUMS.txt"
( cd dist && shasum -a 256 "$(basename "$DMG")" ) > "$SUMS"
echo "==> $DMG"
echo "==> $SUMS"
cat "$SUMS"
