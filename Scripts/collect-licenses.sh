#!/usr/bin/env bash
# Gather the licence text for everything vendored into Resources/engine/.
#
# LGPL and MPL both require that the licence travels with the binary and that
# users can get the source; Apache and BSD require the notice. This walks the
# Homebrew formulae behind the bundled binaries and their dependencies, copies
# each licence out of the Cellar, and writes an index naming every component,
# its SPDX identifier and where its source lives.
#
#   Scripts/collect-licenses.sh [engine_dir]
set -uo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-Resources/engine}"
OUT="LICENSES"
rm -rf "$OUT"; mkdir -p "$OUT"

# Which formulae are we shipping? The binaries we copied, plus everything they
# pull in — the dylibs in libs/ come from those.
roots=()
for f in "$DEST"/*; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  case "$n" in
    7zz) roots+=("sevenzip") ;;
    ffprobe) roots+=("ffmpeg") ;;
    cwebp|dwebp) roots+=("webp") ;;
    *) roots+=("$n") ;;
  esac
done
# de-duplicate
roots=($(printf '%s\n' "${roots[@]}" | sort -u))
[ ${#roots[@]} -eq 0 ] && { echo "nothing in $DEST"; exit 0; }

all=$(brew deps --union --installed "${roots[@]}" 2>/dev/null; printf '%s\n' "${roots[@]}")
all=$(printf '%s\n' $all | sort -u)

{
  echo "# Third-party engines bundled with Kuori"
  echo
  echo "Kuori runs these as separate programs. They keep their own licences,"
  echo "reproduced in this directory. Each was taken unmodified from the Homebrew"
  echo "bottle named below; \`brew fetch --build-from-source <formula>\` retrieves"
  echo "the corresponding source."
  echo
  printf '| Component | Licence | Upstream |\n|---|---|---|\n'
} > "$OUT/NOTICE.md"

count=0
for f in $all; do
  info=$(brew info --json=v2 "$f" 2>/dev/null) || continue
  read -r lic home < <(printf '%s' "$info" | python3 -c "
import sys,json
d=json.load(sys.stdin); fm=(d.get('formulae') or [{}])[0]
print((fm.get('license') or 'see licence file').replace(' ','_'), fm.get('homepage') or '-')
" 2>/dev/null) || continue
  printf '| %s | %s | %s |\n' "$f" "${lic//_/ }" "$home" >> "$OUT/NOTICE.md"

  prefix=$(brew --prefix "$f" 2>/dev/null) || continue
  # -L: brew --prefix hands back /opt/homebrew/opt/<f>, a symlink into the Cellar.
  found=$(find -L "$prefix" -maxdepth 3 \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
            -type f -size -200k 2>/dev/null | head -4)
  if [ -n "$found" ]; then
    mkdir -p "$OUT/$f"
    while IFS= read -r l; do cp -f "$l" "$OUT/$f/$(basename "$l")" 2>/dev/null; done <<< "$found"
    count=$((count+1))
  fi
done

{
  echo
  echo "## Relinking"
  echo
  echo "The LGPL components are shipped as separate dylibs in"
  echo "\`Kuori.app/Contents/Resources/engine/libs/\`, loaded through"
  echo "\`@loader_path\`. Replacing one with your own build is enough to relink —"
  echo "no part of Kuori is statically linked against them."
} >> "$OUT/NOTICE.md"

echo "  $OUT: $count component licences + NOTICE.md"
