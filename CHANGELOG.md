# Changelog

## 0.3.0 — Phases 3–5 (unreleased)

- **Bundled engines**: `Scripts/collect-dylibs.py` (a deterministic
  dylibbundler replacement) vendors ffmpeg, ffprobe, vips, qpdf, 7zz, unar,
  resvg, potrace and pandoc plus ~86 dylibs into `Resources/engine/`, rewriting
  every install name and stray rpath to `@loader_path`. `Kuori.app` now runs
  every route with nothing on `PATH` (verified: webp/avif/heic/svg-trace/gif,
  md→html/docx/rtf, OCR, resize). DMG ≈ 101 MB.
- HEIC/AVIF (both directions) route to macOS ImageIO — the vips bottle has no
  libheif module.
- Bundled binaries launch with `GIO_MODULE_DIR` etc. pointed away from any
  Homebrew glib, so vips never cross-loads a second libgio.
- Fix: `Converter.execute` is now a protocol requirement, so multi-step routes
  (e.g. `md → html`) dispatch to `DocConverter` instead of the no-op default.


- **Documents**: pandoc for md/html/rtf/txt/epub/docx/odt round-trips;
  LibreOffice (bring-your-own) for Office ↔ PDF fidelity; PDF → txt native.
  pptx/xlsx/odp/ods registered. Multi-step routes (Markdown → PDF) handled in
  `DocConverter.execute`.
- **Presets** (`Presets`, `presets.json`): named format + options, `kuori
  convert --preset`, `kuori presets`. Six built-ins.
- **Recipes** (`Recipe` / `RecipeRunner`, `recipes.json`): ordered convert/tool
  pipelines chained through temp files. `kuori recipe`, HUD Recipes mode. Five
  built-ins.
- **Watch folders** (`WatchFolders`, FSEvents, in-process): auto-convert new
  files by format or recipe, move originals to `_processed/`. `kuori watch
  add|list|remove|run`, Settings table.
- **Native tools**: OCR → searchable PDF (Vision text layer, invisible), Remove
  background (VisionKit foreground mask → transparent PNG).
- **Settings window**: login toggle (`SMAppService`), watch-folder editor,
  presets/recipes JSON shortcuts.
- **HUD**: Tab now cycles Convert → Tools → Recipes.
- **Distribution**: `build-app.sh --universal`, `make-dmg.sh`, `notarize.sh`,
  GitHub Actions CI on `macos-15`.
- 48 self-test checks.

## 0.2.0 — Phase 2 (unreleased)

- **Tools** (`⌥` in the HUD / `kuori tool …`): Resize, Compress, Crop-to-aspect,
  Strip metadata, Trim (A/V), Merge PDF, Split PDF — same-format edits that write
  a new file (`name-resized.jpg`). Presets (¼ / ½ / ≤1920 …, Light/Medium/Strong,
  1:1 / 4:5 / 16:9 / 9:16).
- **Raster → SVG** trace: potrace fed a PGM that `NativeOps` rasterizes
  in-process, so it works without libvips.
- **PDF**: merge (PDFs + images), split (page per file), compress (downsample +
  rebuild), strip metadata — all via PDFKit, no binaries.
- **HUD redesign**: frameless card, keyboard-driven (arrows move · ↵ run · ⌥
  Tools · Tab locks mode · esc close), category-grouped format tiles, a thin
  progress bar, auto-dismiss on success. Still one ink / one paper.
- `kuori tool|merge|split` on the CLI; `Kuori --shot-ui <png> [dark] [tools]`.

## 0.1.0 — Phase 1 (unreleased)

First working slice.

- Conversion engine with a declarative capability graph (`Sources/Kuori/Core/Engine.swift`).
- Converters: images (libvips + ImageIO fallback), audio/video (ffmpeg),
  video → GIF, images ↔ PDF (PDFKit), folder ↔ zip/tar/tar.gz/7z, archive extraction.
- `kuori` CLI: `convert`, `formats`, `info` — same path the GUI uses.
- Menu-bar app with a floating Drop Zone; multi-file drops offer the intersection
  of each file's routes. Finder Services entry ("Convert with Kuori…").
- `Kuori --selftest`: format resolution, graph integrity, argument builders,
  output naming/collision, engine availability report.
- `Scripts/build-app.sh` (arm64, ad-hoc signed), `Scripts/bundle-engines.sh`
  (dylib relocation), `Scripts/makeicon.swift` (icon drawn in code).
- RAR creation explicitly refused (no licensable encoder).
