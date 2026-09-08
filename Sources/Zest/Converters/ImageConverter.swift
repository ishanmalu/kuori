import Foundation

/// Raster images via libvips, with an ImageIO fallback when vips isn't present.
/// SVG rasterizing via resvg. Raster→SVG (trace) is Phase 2.
struct ImageConverter: Converter {
    static let raster = ["jpg", "png", "webp", "heic", "avif", "tiff", "bmp", "gif"]
    static let imageIOWritable: Set<String> = ["jpg", "png", "tiff", "heic", "gif", "bmp"]

    func targets(for input: Format) -> [Format] {
        guard input.category == .image else { return [] }
        if input.id == "svg" {
            return Self.raster.compactMap { Formats.byID[$0] }
        }
        var ids = Set(Self.raster)
        ids.remove(input.id)
        return ids.compactMap { Formats.byID[$0] }
    }

    func plan(input: URL, from: Format, to: Format, output: URL, opts: ConvertOptions) throws -> Invocation {
        if from.id == "svg" {
            var a = [input.path, "-o", output.path]
            if let w = opts.scaleWidth { a += ["--width", String(w)] }
            return Invocation(engine: .resvg, args: a)
        }

        // Prefer vips; fall back to in-process ImageIO when it's unavailable.
        if EngineLocator.path(for: .vips) == nil {
            guard Self.imageIOWritable.contains(to.id) else {
                throw ConvertError.engineMissing(.vips)
            }
            return Invocation(engine: .native, nativeKind: .imageIO(to))
        }

        var op: [String]
        if let w = opts.scaleWidth {
            op = ["thumbnail", input.path, output.path, String(w)]
        } else {
            op = ["copy", input.path, output.path]
        }

        // vips save options ride on the output filename: out.jpg[Q=80,strip]
        var saveOpts: [String] = []
        if let q = opts.quality, ["jpg", "webp", "heic", "avif", "tiff"].contains(to.id) {
            saveOpts.append("Q=\(q)")
        }
        if opts.stripMetadata { saveOpts.append("strip") }
        if !saveOpts.isEmpty {
            op[op.count - 1] += "[\(saveOpts.joined(separator: ","))]"
        }
        return Invocation(engine: .vips, args: op)
    }
}
