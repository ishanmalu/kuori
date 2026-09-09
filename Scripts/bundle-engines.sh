#!/usr/bin/env bash
# Pull the conversion engines into Resources/engine/ and make them self-contained.
#
#   Scripts/bundle-engines.sh            # default set
#   Scripts/bundle-engines.sh ffmpeg     # just one
#
# Copies the current Homebrew binaries, then Scripts/collect-dylibs.py walks
# `otool -L`, vendors every non-system dylib into Resources/engine/libs/, and
# rewrites install names + rpaths to @loader_path.
#
# The default set is deliberately GPL-free, so the DMG carries no source-offer
# obligation. Left out on purpose:
#
#   ffmpeg    GPL-3    pandoc, potrace   GPL-2
#   vips      LGPL itself, but its bottle hard-links libfftw3 (GPL-2) and
#             libimagequant (GPL-3); dropping either dylib stops vips loading.
#
# WebP is the only format ImageIO decodes but can't encode, so cwebp (BSD-3)
# stands in for vips there. Everything else vips did is native. Kuori still
# finds the omitted engines on PATH, so pass them explicitly for a full build:
#
#   Scripts/bundle-engines.sh ffmpeg ffprobe potrace pandoc vips qpdf 7zz unar resvg cwebp
#
# LibreOffice is never bundled — the app looks for a /Applications install.
set -uo pipefail
cd "$(dirname "$0")/.."

DEST="Resources/engine"
DEFAULT_SET=(cwebp qpdf 7zz unar resvg)
if [ "$#" -gt 0 ]; then WANT=("$@"); else WANT=("${DEFAULT_SET[@]}"); fi

command -v brew >/dev/null || { echo "Homebrew required"; exit 1; }
mkdir -p "$DEST"

real() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

for name in "${WANT[@]}"; do
  src="$(command -v "$name" 2>/dev/null || true)"
  [ -z "$src" ] && src="$(command -v "${name/7zz/7z}" 2>/dev/null || true)"
  if [ -z "$src" ] || [ ! -x "$src" ]; then echo "skip  $name (not installed)"; continue; fi
  cp -f "$(real "$src")" "$DEST/$name"
  chmod u+w "$DEST/$name"
  echo "copied $name  <-  $(real "$src")"
done

echo "==> collecting dylibs"
python3 Scripts/collect-dylibs.py "$DEST"

echo "==> writing LICENSES/"
Scripts/collect-licenses.sh "$DEST"

du -sh "$DEST"
