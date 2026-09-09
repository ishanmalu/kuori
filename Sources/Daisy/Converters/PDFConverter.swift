import Foundation

/// PDF routes handled entirely in-process by PDFKit / ImageIO — no binaries.
/// image → PDF (single page) and PDF → image (one file per page, into a folder).
struct PDFConverter: Converter {
    func targets(for input: Format) -> [Format] {
        switch input.id {
        case "pdf":
            return ["png", "jpg", "tiff"].compactMap { Formats.byID[$0] } + [Formats.byID["folder"]!]
        case "svg":
            return []   // no raster to embed; go svg → png → pdf
        default:
            return input.category == .image ? [Formats.byID["pdf"]!] : []
        }
    }

    func writesDirectory(from: Format, to: Format) -> Bool { from.id == "pdf" }

    func plan(input: URL, from: Format, to: Format, output: URL, opts: ConvertOptions) throws -> Invocation {
        if from.id == "pdf" {
            let imageFmt = to.id == "folder" ? Formats.byID["png"]! : to
            return Invocation(engine: .native, producesDirectory: true,
                              nativeKind: .pdfRasterize(imageFmt))
        }
        if to.id == "pdf" {
            return Invocation(engine: .native, nativeKind: .pdfFromImages)
        }
        throw ConvertError.unsupported(from: from.id, to: to.id)
    }
}
