#!/usr/bin/env bash
# Pulls the conversion engines into Resources/engine/ with their dylibs
# relocated to @loader_path, so Zest.app is self-contained.
#
#   Scripts/bundle-engines.sh            # ffmpeg vips qpdf exiftool 7zz unar (default set)
#   Scripts/bundle-engines.sh ffmpeg     # just one
#
# Needs Homebrew for the source binaries and `dylibbundler`
# (brew install dylibbundler). LibreOffice is intentionally NOT bundled here —
# the app downloads it on demand into ~/Library/Application Support/Zest/engine.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="Resources/engine"
DEFAULT_SET=(ffmpeg ffprobe vips qpdf exiftool 7zz unar lsar resvg potrace pandoc)
WANT=("${@:-${DEFAULT_SET[@]}}")

command -v brew >/dev/null || { echo "Homebrew required"; exit 1; }
command -v dylibbundler >/dev/null || { echo "run: brew install dylibbundler"; exit 1; }

mkdir -p "$DEST/libs"

resolve() {
  # map our engine name to a brew binary path
  case "$1" in
    ffmpeg|ffprobe) command -v "$1" ;;
    vips)           command -v vips ;;
    7zz)            command -v 7zz || command -v 7z ;;
    *)              command -v "$1" || true ;;
  esac
}

for name in "${WANT[@]}"; do
  src="$(resolve "$name" || true)"
  if [ -z "$src" ] || [ ! -x "$src" ]; then
    echo "skip  $name (not installed)"
    continue
  fi
  echo "bundle $name  <-  $src"
  cp "$src" "$DEST/$name"
  chmod +w "$DEST/$name"
  dylibbundler -of -b -x "$DEST/$name" -d "$DEST/libs" -p '@loader_path/libs/' >/dev/null
  codesign --force --sign - "$DEST/$name"
done

find "$DEST/libs" -name '*.dylib' -exec codesign --force --sign - {} \; 2>/dev/null || true

echo "==> $DEST populated. Verify no absolute paths leaked:"
find "$DEST" -type f -perm -u+x -exec sh -c 'otool -L "$1" | grep -q /opt/homebrew && echo "  LEAK: $1"' _ {} \; || true
echo "    (no LEAK lines above = good)"
