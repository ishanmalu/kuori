# Changelog

## 0.6.1

- **The wheel blooms open.** A ring of accent light flares past the rim and
  burns off in about half a second as the disc scales up. It's a ring rather
  than a filled glow because the disc is opaque — a bloom that peaks in the
  middle is hidden behind it, so the light peaks at the rim instead. The window
  grew from 300 to 360pt to give it somewhere to go, and the blur, which carries
  the circular mask, moved into an unmasked container: anything parented to a
  masked view gets clipped by that mask too.
- **Bloom on the site as well**, on scroll reveal — a brief brightness-and-blur
  on each block plus a radial wash behind it. Code blocks are excluded; blurred
  monospace is just mush.
- **Contrast pass.** Every text node on the site now clears WCAG AA. `--faint`
  was 3.31:1 against the page and used all over, and the download button's
  subtitle was 3.66:1 dark-on-yellow. Both fixed, along with the footer tagline
  and the coffee link.
- Fix: the formats section still claimed nine engines are bundled and that
  nothing needs installing. Neither has been true since 0.4.0.

## 0.6.0 — Daisy

Kuori is now **Daisy**. The name was a Finnish pun on *peel*, inherited from
being a Tangerine alternative; the wheel long ago stopped being citrus and
became a ring of petals around a centre, so the name now describes the thing
itself.

- **White petals, yellow centre.** The petals are near-opaque on purpose — a
  translucent white over a dark desktop turns grey, and grey petals aren't a
  daisy — so the glass shows in the gaps between them and around the rim. The
  centre is a vertical gradient rather than a flat fill, and the progress pill
  inverts to accent-on-dark because it sits on top of it.
- Icon and menu-bar glyph redrawn from the wheel's own geometry, so the mark and
  the UI can't drift apart.
- Everything renamed: `daisy` on the command line, `com.ishanmalu.daisy`,
  `~/Library/Application Support/Daisy`, the hotkey's four-char code. **An
  existing install keeps its config under the old Kuori folder** — this is a
  fresh directory, not a migration. Copy `presets.json`, `recipes.json` and
  `watch.json` across if you had any.
- `--demo` takes `tools` / `recipes` too, which is how the site screenshots are
  taken.

## 0.5.0

- **Click to choose.** The empty ring is a button now: click it (or press ↵, or
  ⌘O) and Finder's own picker opens. Dragging is still the fast path, but the
  wheel no longer requires knowing about Shift-drag to be usable. New menu-bar
  item, **Convert File…**, does both in one step.
- **Folder drops do the obvious thing.** Drop a folder of photos and the wheel
  offers image targets for everything inside it *and* the archive targets for
  the folder itself — convert 40 images, or zip the folder, from the same wheel.
  Shallow, name-ordered, hidden files and subfolders skipped.
- **Liquid glass.** The wheel is a real behind-window blur clipped to the disc,
  with a lit top rim and a shaded underside so the edge reads as thick. Petals
  are translucent with their own specular edge; the hub is denser so a thumbnail
  has something to sit on. It rises into place with a short spring rather than
  blinking on.
- The empty ring warms its dashed edge and takes a pointing-hand cursor when the
  mouse is over it.
- `InputSet` lifts folder-expansion policy out of the view, where it's testable;
  nine new checks cover it. 63 in total.
- New `--demo <files…> [light|dark]` holds the wheel open over the live desktop.
  `--shot-ui` caches the view offscreen, which a behind-window blur can't
  survive, so this is the only way to see the real thing.

## 0.4.0

- **Licence: PolyForm Noncommercial 1.0.0.** Daisy is free to use, read, modify
  and pass around for anything that isn't commercial. Commercial use is a
  conversation, not a download.
- **The bundle is GPL-free.** ffmpeg, pandoc and potrace are gone from the DMG
  (GPL-3 / GPL-2), and so is libvips — its bottle hard-links libfftw3 (GPL-2)
  and libimagequant (GPL-3), and removing either dylib stops vips loading at
  all. Daisy still finds every one of them on `PATH`; only redistribution
  changed. `Resources/engine` went 350 MB → 20 MB.
- **cwebp (BSD-3) replaces vips for WebP**, the one raster format macOS decodes
  but won't encode. Any input ImageIO can read is staged through a temp PNG
  first, so HEIC → WebP and friends still work, with quality, resize, EXIF
  preservation and `--strip` all behaving as before.
- `Scripts/collect-licenses.sh` walks the formulae behind the bundle and writes
  `LICENSES/NOTICE.md` — component, SPDX identifier, upstream — plus the licence
  texts themselves.
- Fix: `brew install` hints in engine-missing errors now name the formula rather
  than the binary (`webp`, not `cwebp`).

## 0.3.1

- Universal binary — the app now carries both arm64 and x86_64 slices.
- `EngineLocator` reads each engine's Mach-O header and skips slices it can't
  run, so the arm64 bundled engines are ignored on Intel and the search falls
  through to `/usr/local/bin` instead of trying to exec something that can't
  start. Applies to all three lookup tiers.
- Verified by running the x86_64 slice under Rosetta: 54/54 checks, bundled
  engines correctly skipped, native routes (ImageIO, PDFKit, Vision, bsdtar)
  all still converting.

## 0.3.0

- **Radial HUD**, à la Tangerine: the source file sits in the hub and the
  targets fan out as rounded citrus-segment petals. Click a petal, or arrow to
  it and press ↵. Icons on tool petals. ⌥ swaps Convert → Tools; ⇥ cycles
  Convert / Tools / Recipes; a tool with presets opens its presets as a
  sub-wheel (esc backs out). Still one ink / one paper, light + dark.
- **Bundled engines**: `Scripts/collect-dylibs.py` (a deterministic
  dylibbundler replacement) vendors ffmpeg, ffprobe, vips, qpdf, 7zz, unar,
  resvg, potrace and pandoc plus ~86 dylibs into `Resources/engine/`, rewriting
  every install name and stray rpath to `@loader_path`. `Daisy.app` now runs
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
- **Presets** (`Presets`, `presets.json`): named format + options, `daisy
  convert --preset`, `daisy presets`. Six built-ins.
- **Recipes** (`Recipe` / `RecipeRunner`, `recipes.json`): ordered convert/tool
  pipelines chained through temp files. `daisy recipe`, HUD Recipes mode. Five
  built-ins.
- **Watch folders** (`WatchFolders`, FSEvents, in-process): auto-convert new
  files by format or recipe, move originals to `_processed/`. `daisy watch
  add|list|remove|run`, Settings table.
- **Native tools**: OCR → searchable PDF (Vision text layer, invisible), Remove
  background (VisionKit foreground mask → transparent PNG).
- **Settings window**: login toggle (`SMAppService`), watch-folder editor,
  presets/recipes JSON shortcuts.
- **HUD**: Tab now cycles Convert → Tools → Recipes.
- **Distribution**: `build-app.sh --universal`, `make-dmg.sh`, `notarize.sh`,
  GitHub Actions CI on `macos-15`.
- 48 self-test checks.

## 0.2.0

- **Tools** (`⌥` in the HUD / `daisy tool …`): Resize, Compress, Crop-to-aspect,
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
- `daisy tool|merge|split` on the CLI; `Daisy --shot-ui <png> [dark] [tools]`.

## 0.1.0

First working slice.

- Conversion engine with a declarative capability graph (`Sources/Daisy/Core/Engine.swift`).
- Converters: images (libvips + ImageIO fallback), audio/video (ffmpeg),
  video → GIF, images ↔ PDF (PDFKit), folder ↔ zip/tar/tar.gz/7z, archive extraction.
- `daisy` CLI: `convert`, `formats`, `info` — same path the GUI uses.
- Menu-bar app with a floating Drop Zone; multi-file drops offer the intersection
  of each file's routes. Finder Services entry ("Convert with Daisy…").
- `Daisy --selftest`: format resolution, graph integrity, argument builders,
  output naming/collision, engine availability report.
- `Scripts/build-app.sh` (arm64, ad-hoc signed), `Scripts/bundle-engines.sh`
  (dylib relocation), `Scripts/makeicon.swift` (icon drawn in code).
- RAR creation explicitly refused (no licensable encoder).
