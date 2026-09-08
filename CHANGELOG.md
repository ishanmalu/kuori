# Changelog

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
