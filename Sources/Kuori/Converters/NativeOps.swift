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
        default:     return nil
        }
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
        guard h > 0, let cs = image.colorSpace,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: image.bitmapInfo.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
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
}
