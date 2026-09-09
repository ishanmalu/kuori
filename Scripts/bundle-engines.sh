#!/usr/bin/env bash
# Pull the conversion engines into Resources/engine/ and make them self-contained.
#
#   Scripts/bundle-engines.sh            # default set
#   Scripts/bundle-engines.sh ffmpeg     # just one
#
# Copies the current Homebrew binaries, then Scripts/collect-dylibs.py walks
# `otool -L`, vendors every non-system dylib into Resources/engine/libs/, and
# rewrites install names + rpaths to @loader_path. LibreOffice is NOT bundled —
# the app finds a /Applications install on demand.
set -uo pipefail
cd "$(dirname "$0")/.."

DEST="Resources/engine"
DEFAULT_SET=(ffmpeg ffprobe vips qpdf 7zz unar resvg potrace pandoc)
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
du -sh "$DEST"
