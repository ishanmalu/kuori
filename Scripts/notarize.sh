#!/usr/bin/env bash
# Notarize dist/Daisy-<version>.dmg with a Developer ID. Optional — the app runs
# ad-hoc-signed for personal use; this is only for distributing without the
# Gatekeeper prompt.
#
# Prereqs: a "Developer ID Application" cert in the login keychain, and a stored
# notary profile:  xcrun notarytool store-credentials daisy-notary \
#                    --apple-id you@example.com --team-id XXXXXXXXXX
#
# Usage: DAISY_SIGN_ID="Developer ID Application: Name (TEAMID)" Scripts/notarize.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.3.0}"
APP="dist/Daisy.app"
DMG="dist/Daisy-$VERSION.dmg"
: "${DAISY_SIGN_ID:?set DAISY_SIGN_ID to your Developer ID Application identity}"

codesign --force --deep --options runtime --timestamp --sign "$DAISY_SIGN_ID" "$APP"
Scripts/make-dmg.sh "$VERSION"
xcrun notarytool submit "$DMG" --keychain-profile daisy-notary --wait
xcrun stapler staple "$DMG"
echo "==> notarized + stapled $DMG"
