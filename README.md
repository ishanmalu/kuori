# Kuori

A local file converter for macOS — a personal, faster, scriptable take on
[Tangerine](https://tangerineformac.com/). *Kuori* is Finnish for **peel / rind**:
you drop a file in and the format comes away.

Menu-bar HUD plus a `kuori` CLI that share one conversion engine. Nothing is
uploaded anywhere. Built like [Perch](https://github.com/ishanmalu/perch):
Swift + AppKit, SwiftPM, **no Xcode**, ad-hoc-signed. Checks run as
`Kuori --selftest` (XCTest isn't in the Command Line Tools SDK).

## What it does

**Convert** — drop files, pick a format petal (only the ones every dropped file
can produce):

| Class | Routes | Engine |
|---|---|---|
| Images | jpg png webp heic avif tiff bmp gif ↔ each other; svg → raster; raster → svg (trace) | libvips / ImageIO / resvg / potrace |
| Audio | mp3 m4a aac wav flac ogg opus aiff ↔ each other | ffmpeg |
| Video | mp4 mov mkv webm avi m4v ↔ each other; → gif; → audio | ffmpeg |
| Documents | md html rtf txt epub docx odt ↔ each other; office → pdf; pdf → txt/docx | pandoc / LibreOffice / PDFKit |
| PDF | images → pdf; pdf → png/jpg/tiff | PDFKit |
| Archives | folder ↔ zip / tar / tar.gz / 7z; extract zip/tar/7z/rar → folder | bsdtar / 7zz |

**Tools** (hold ⌥, or Tab) — same-format edits that write a new file:
Resize · Compress · Crop-to-aspect · Strip metadata · Trim (A/V) ·
**OCR → searchable PDF** (Vision) · **Remove background** (VisionKit) ·
Merge PDF · Split PDF.

**Recipes** (Tab again) — saved multi-step pipelines (`web-image`, `square-jpg`,
`reel-to-mp4`, `clip-to-gif`, `scan-to-ocr-pdf`), editable in `recipes.json`.

**Watch folders** — anything dropped into a watched folder is converted (by
format or by recipe) and the original moved to `_processed/`. Runs in-process;
add them in Settings or `kuori watch add`.

**RAR creation is not supported** — no licensable RAR encoder. Use ZIP or 7z.

## HUD

A radial wheel, like Tangerine — the file in the hub, targets fanning out as
petals. Monochrome, keyboard-driven:

```
← → move    ↵ run    ⌥ Tools    ⇥ cycle Convert / Tools / Recipes    esc
```

Click a petal or arrow to it and press ↵. Drops and ⌘V both load files. Runs
happen on a background queue with a progress readout and auto-dismiss on
success.

## Build & run

```sh
swift run Kuori --selftest             # 50 graph + logic checks
Scripts/build-app.sh 0.3.0             # -> dist/Kuori.app  (add --universal for arm64+x86_64)
Scripts/make-dmg.sh 0.3.0             # -> dist/Kuori-0.3.0.dmg
open dist/Kuori.app                    # menu-bar icon -> Drop Zone / Settings
```

## CLI

```sh
kuori convert photo.png --to webp --quality 80
kuori convert *.jpg --to pdf --out ~/Desktop
kuori convert in.png out.avif                     # target inferred from the name
kuori convert shot.png --preset web-jpg           # saved preset
kuori tool resize clip.mov --preset "½"
kuori tool ocr scan.png                           # -> scan-ocr.pdf, searchable
kuori tool removeBackground portrait.jpg          # -> portrait-nobg.png
kuori merge a.pdf b.pdf ; kuori split book.pdf
kuori recipe square-jpg *.png
kuori watch add ~/Dropbox/Incoming --to webp
kuori presets ; kuori recipes ; kuori formats ; kuori info movie.mkv
```

## Bundled engines

The app finds Homebrew copies on a dev machine. For a self-contained `.app`
(~350 MB, DMG ~100 MB):

```sh
brew install ffmpeg vips qpdf sevenzip unar resvg potrace pandoc
Scripts/bundle-engines.sh             # copies the binaries, then collect-dylibs.py
                                     #   vendors ~86 dylibs into Resources/engine/libs/
                                     #   and rewrites install names to @loader_path
Scripts/build-app.sh 0.3.0
```

`Scripts/collect-dylibs.py` is a small deterministic stand-in for `dylibbundler`
(walks `otool -L`, copies, `install_name_tool`s, strips package-manager rpaths).
HEIC/AVIF go through macOS ImageIO — the vips bottle ships without libheif.

**LibreOffice** is bring-your-own: install it under `/Applications` (or drop a
copy in `~/Library/Application Support/Kuori/engine/`) and Office↔PDF fidelity
conversions light up. Never auto-downloaded.

Engine licenses live in `LICENSES/`.

## License

MIT — see `LICENSE`. Bundled engines keep their own licenses.
