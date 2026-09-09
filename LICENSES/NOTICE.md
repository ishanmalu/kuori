# Third-party engines bundled with Kuori

Kuori runs these as separate programs. They keep their own licences,
reproduced in this directory. Each was taken unmodified from the Homebrew
bottle named below; `brew fetch --build-from-source <formula>` retrieves
the corresponding source.

| Component | Licence | Upstream |
|---|---|---|
| ca-certificates | MPL-2.0 | https://curl.se/docs/caextract.html |
| giflib | MIT | https://giflib.sourceforge.net/ |
| jpeg-turbo | IJG AND Zlib AND BSD-3-Clause | https://www.libjpeg-turbo.org/ |
| libpng | libpng-2.0 | https://www.libpng.org/pub/png/libpng.html |
| qpdf | Apache-2.0 | https://qpdf.sourceforge.io/ |
| resvg | MPL-2.0 | https://github.com/linebender/resvg |
| sevenzip | LGPL-2.1-or-later AND BSD-3-Clause | https://7-zip.org |
| unar | LGPL-2.1-or-later | https://theunarchiver.com/command-line |
| webp | BSD-3-Clause | https://developers.google.com/speed/webp/ |

## Relinking

The LGPL components are shipped as separate dylibs in
`Kuori.app/Contents/Resources/engine/libs/`, loaded through
`@loader_path`. Replacing one with your own build is enough to relink —
no part of Kuori is statically linked against them.
