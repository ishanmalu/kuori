# Kuori

A local file converter for macOS — a personal, faster, scriptable take on
[Tangerine](https://tangerineformac.com/). Menu-bar app plus a `kuori` CLI that
share one conversion engine. Nothing is uploaded anywhere.

Built the same way as [Perch](https://github.com/ishanmalu/perch): Swift + AppKit,
SwiftPM, **no Xcode**, ad-hoc-signed. Safety checks run as `Kuori --selftest`
(XCTest isn't in the Command Line Tools SDK).

## Status

Phase 1 — the conversion core works end to end:

| Class | Routes | Engine |
|---|---|---|
| Images | jpg png webp heic avif tiff bmp gif ↔ each other, svg → raster | libvips (ImageIO fallback) |
| Audio | mp3 m4a aac wav flac ogg opus aiff ↔ each other | ffmpeg |
| Video | mp4 mov mkv webm avi m4v ↔ each other, → gif, → audio | ffmpeg |
| PDF | images → PDF, PDF → png/jpg/tiff (page per file) | PDFKit (in-process) |
| Archives | folder ↔ zip / tar / tar.gz / 7z, extract zip/tar/7z/rar → folder | bsdtar, 7zz |

Planned: raster → SVG trace, PDF merge/split/compress, DOCX/PPTX/XLSX (pandoc +
on-demand LibreOffice), presets, multi-step recipes, watch folders, native OCR
and background removal, universal build + DMG. See the plan in the project notes.

**RAR creation is not supported** — there's no licensable RAR encoder. Use ZIP or 7z.

## Build & run

```sh
swift run Kuori --selftest          # graph + arg-builder checks
Scripts/build-app.sh 0.1.0         # -> dist/Kuori.app (arm64, ad-hoc signed)
open dist/Kuori.app                 # menu-bar icon -> "Drop Zone"
```

## CLI

```sh
kuori convert photo.png --to webp --quality 80
kuori convert clip.mov --to gif --scale 600x
kuori convert *.jpg --to pdf --out ~/Desktop
kuori convert in.png out.avif        # target inferred from the output name
kuori formats                        # what converts to what
kuori info movie.mkv
```

`--strip` removes metadata where the engine supports it. Collisions get a
` 2`, ` 3` suffix unless you pass `--overwrite` or `--skip-existing`.

## Bundled engines

The app finds Homebrew copies on a dev machine. For a self-contained `.app`:

```sh
brew install ffmpeg vips qpdf exiftool sevenzip unar dylibbundler
Scripts/bundle-engines.sh           # -> Resources/engine/ with dylibs relocated
Scripts/build-app.sh 0.1.0
```

Engine licenses live in `LICENSES/`. LibreOffice is downloaded on first use into
`~/Library/Application Support/Kuori/engine`, never shipped in the bundle.

## License

MIT — see `LICENSE`. Bundled engines keep their own licenses.
