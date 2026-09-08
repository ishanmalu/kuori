import Foundation
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// In-process conversions backed by macOS frameworks. No bundled binary.
enum NativeOps {
    static func perform(_ kind: NativeKind, input: URL, output: URL, opts: ConvertOptions) throws {
        switch kind {
        case .imageIO(let target):
            try writeImage(from: input, to: output, target: target, opts: opts)
        case .pdfFromImages:
            try pdfFromImages([input], to: output)
        case .pdfRasterize(let target):
            try rasterizePDF(input, into: output, target: target, opts: opts)
        }
    }

    // MARK: - Images

    private static func utType(for id: String) -> UTType? {
        switch id {
        case "jpg":  return .jpeg
        case "png":  return .png
        case "tiff": return .tiff
        case "heic": return .heic
        case "gif":  return .gif
        case "bmp":  return .bmp
        case "webp": return UTType("org.webmproject.webp")
        case "avif": return UTType("public.avif")
        default:     return nil
        }
    }

    private static func writeCGImage(_ image: CGImage, to output: URL, id: String, quality: Int?) throws {
        guard let type = utType(for: id),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.badInput("The built-in encoder can't write \(id.uppercased()). Install vips.")
        }
        var props: [CFString: Any] = [:]
        if let q = quality, ["jpg", "heic", "webp", "avif"].contains(id) {
            props[kCGImageDestinationLossyCompressionQuality] = Double(q) / 100.0
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)   // no source metadata carried over
        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.badInput("Failed to write \(output.lastPathComponent)")
        }
    }

    private static func loadCGImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ConvertError.badInput("Couldn't read image: \(url.lastPathComponent)")
        }
        return img
    }

    private static func writeImage(from input: URL, to output: URL, target: Format, opts: ConvertOptions) throws {
        guard let type = utType(for: target.id) else {
            throw ConvertError.badInput("The built-in encoder can't write \(target.label). Install vips.")
        }
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ConvertError.badInput("Couldn't read image: \(input.lastPathComponent)")
        }
        if let w = opts.scaleWidth, w > 0, w < image.width {
            image = resized(image, toWidth: w) ?? image
        }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.badInput("Couldn't create \(output.lastPathComponent)")
        }
        var props: [CFString: Any] = [:]
        if let q = opts.quality, target.id == "jpg" || target.id == "heic" {
            props[kCGImageDestinationLossyCompressionQuality] = Double(q) / 100.0
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.badInput("Failed to write \(output.lastPathComponent)")
        }
    }

    private static func resized(_ image: CGImage, toWidth w: Int) -> CGImage? {
        let h = Int((Double(image.height) * Double(w) / Double(image.width)).rounded())
        return redraw(image, width: w, height: max(1, h))
    }

    private static func redraw(_ image: CGImage, width w: Int, height h: Int) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Same-format image tools (resize / crop / compress / strip)

    static func editImage(_ input: URL, to output: URL, tool: Tool, params: ToolRunner.Params) throws {
        let id = Formats.byURL(output)?.id ?? output.pathExtension.lowercased()
        var image = try loadCGImage(input)

        switch tool {
        case .resize:
            let (w, h): (Int, Int)
            if let p = params.scalePercent {
                w = max(1, image.width * p / 100); h = max(1, image.height * p / 100)
            } else {
                let m = params.maxEdge ?? 1280
                let longest = max(image.width, image.height)
                let s = longest > m ? Double(m) / Double(longest) : 1.0
                w = Int(Double(image.width) * s); h = Int(Double(image.height) * s)
            }
            image = redraw(image, width: w, height: h) ?? image

        case .crop:
            let (an, ad) = aspectPair(params.aspect ?? "1:1")
            let iw = CGFloat(image.width), ih = CGFloat(image.height)
            var cw = iw, ch = iw * CGFloat(ad) / CGFloat(an)
            if ch > ih { ch = ih; cw = ih * CGFloat(an) / CGFloat(ad) }
            let rect = CGRect(x: ((iw - cw) / 2).rounded(), y: ((ih - ch) / 2).rounded(),
                              width: cw.rounded(.down), height: ch.rounded(.down))
            image = image.cropping(to: rect) ?? image

        case .compress, .stripMetadata:
            break   // re-encode below; AddImage drops source metadata on its own
        default:
            throw ConvertError.badInput("\(tool.label) doesn't apply to images.")
        }

        let q = tool == .compress ? (params.quality ?? 60) : (tool == .stripMetadata ? nil : params.quality)
        try writeCGImage(image, to: output, id: id, quality: q)
    }

    private static func aspectPair(_ s: String) -> (Int, Int) {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : (1, 1)
    }

    // MARK: - PDF

    static func pdfFromImages(_ images: [URL], to output: URL) throws {
        let doc = PDFDocument()
        var idx = 0
        for url in images {
            guard let img = NSImage(contentsOf: url), let page = PDFPage(image: img) else {
                throw ConvertError.badInput("Couldn't read image: \(url.lastPathComponent)")
            }
            doc.insert(page, at: idx)
            idx += 1
        }
        guard idx > 0, doc.write(to: output) else {
            throw ConvertError.badInput("Failed to write \(output.lastPathComponent)")
        }
    }

    private static func rasterizePDF(_ input: URL, into dir: URL, target: Format, opts: ConvertOptions) throws {
        guard let doc = PDFDocument(url: input) else {
            throw ConvertError.badInput("Couldn't open PDF: \(input.lastPathComponent)")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scale = CGFloat(max(1, min(6, (opts.quality ?? 50) / 20 + 1)))   // ~2x by default
        let stem = Naming.strippedStem(of: input)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let pixels = NSSize(width: box.width * scale, height: box.height * scale)
            guard pixels.width >= 1, pixels.height >= 1 else { continue }

            let img = NSImage(size: pixels)
            img.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: pixels).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            img.unlockFocus()

            let out = dir.appendingPathComponent(String(format: "%@-%03d", stem, i + 1))
                         .appendingPathExtension(target.ext)
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                throw ConvertError.badInput("Failed to render page \(i + 1)")
            }
            let fileType: NSBitmapImageRep.FileType = target.id == "jpg" ? .jpeg : (target.id == "tiff" ? .tiff : .png)
            var repProps: [NSBitmapImageRep.PropertyKey: Any] = [:]
            if target.id == "jpg" {
                repProps[.compressionFactor] = Double(opts.quality ?? 85) / 100.0
            }
            guard let data = rep.representation(using: fileType, properties: repProps) else {
                throw ConvertError.badInput("Failed to encode page \(i + 1)")
            }
            try data.write(to: out)
        }
    }

    // MARK: - PDF tools

    static func pdfMerge(_ inputs: [URL], to output: URL) throws {
        let merged = PDFDocument()
        var page = 0
        for url in inputs {
            if url.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: url) else {
                    throw ConvertError.badInput("Couldn't open PDF: \(url.lastPathComponent)")
                }
                for i in 0..<doc.pageCount {
                    if let p = doc.page(at: i) { merged.insert(p, at: page); page += 1 }
                }
            } else {
                guard let img = NSImage(contentsOf: url), let p = PDFPage(image: img) else {
                    throw ConvertError.badInput("Couldn't read image: \(url.lastPathComponent)")
                }
                merged.insert(p, at: page); page += 1
            }
        }
        guard page > 0, merged.write(to: output) else {
            throw ConvertError.badInput("Failed to write \(output.lastPathComponent)")
        }
    }

    static func pdfSplit(_ input: URL, into dir: URL) throws {
        guard let doc = PDFDocument(url: input) else {
            throw ConvertError.badInput("Couldn't open PDF: \(input.lastPathComponent)")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = Naming.strippedStem(of: input)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let one = PDFDocument()
            one.insert(page, at: 0)
            let out = dir.appendingPathComponent(String(format: "%@-%03d.pdf", stem, i + 1))
            guard one.write(to: out) else { throw ConvertError.badInput("Failed to write page \(i + 1)") }
        }
    }

    /// Downsample every page to a JPEG and rebuild — the usual "shrink a PDF" trick.
    static func pdfCompress(_ input: URL, to output: URL, quality: Int) throws {
        guard let doc = PDFDocument(url: input) else {
            throw ConvertError.badInput("Couldn't open PDF: \(input.lastPathComponent)")
        }
        let dpiScale: CGFloat = quality >= 75 ? 2.0 : (quality >= 50 ? 1.5 : 1.1)
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let px = NSSize(width: max(1, box.width * dpiScale), height: max(1, box.height * dpiScale))
            let img = NSImage(size: px)
            img.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: px).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState(); ctx.scaleBy(x: dpiScale, y: dpiScale)
                ctx.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: ctx); ctx.restoreGState()
            }
            img.unlockFocus()
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: Double(quality) / 100.0]),
                  let jImg = NSImage(data: jpeg), let pg = PDFPage(image: jImg) else {
                throw ConvertError.badInput("Failed to compress page \(i + 1)")
            }
            out.insert(pg, at: i)
        }
        guard out.write(to: output) else { throw ConvertError.badInput("Failed to write \(output.lastPathComponent)") }
    }

    static func pdfStripMetadata(_ input: URL, to output: URL) throws {
        guard let doc = PDFDocument(url: input) else {
            throw ConvertError.badInput("Couldn't open PDF: \(input.lastPathComponent)")
        }
        doc.documentAttributes = [:]
        guard doc.write(to: output) else { throw ConvertError.badInput("Failed to write \(output.lastPathComponent)") }
    }

    // MARK: - Grayscale PGM (feeds potrace for raster → SVG)

    static func writeGrayPGM(_ input: URL, to output: URL, maxEdge: Int = 1600) throws {
        var image = try loadCGImage(input)
        let longest = max(image.width, image.height)
        if longest > maxEdge {
            let s = Double(maxEdge) / Double(longest)
            image = redraw(image, width: Int(Double(image.width) * s), height: Int(Double(image.height) * s)) ?? image
        }
        let w = image.width, h = image.height
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw ConvertError.badInput("Couldn't rasterize \(input.lastPathComponent)")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var data = Data("P5\n\(w) \(h)\n255\n".utf8)
        // PGM rows run top-to-bottom; CGContext buffer is bottom-up, so flip.
        for row in stride(from: h - 1, through: 0, by: -1) {
            data.append(contentsOf: gray[(row * w)..<(row * w + w)])
        }
        try data.write(to: output)
    }
}
