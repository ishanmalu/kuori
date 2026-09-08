# Changelog

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
