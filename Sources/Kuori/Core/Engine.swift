import Foundation

/// Conversion back-ends. `native` means "handled in-process by macOS frameworks"
/// (ImageIO / PDFKit / Vision) — no bundled binary required.
enum EngineID: String {
    case ffmpeg, vips, resvg, potrace, pandoc, libreoffice, qpdf
    case sevenzip = "7zz"
    case unar, bsdtar, exiftool
    case native
}

struct ConvertOptions {
    var quality: Int? = nil          // 1...100 where the target supports it
    var scale: String? = nil         // "WIDTHxHEIGHT", either side may be blank
    var stripMetadata: Bool = false
    var extra: [String] = []         // passed through verbatim to the engine

    var scaleWidth: Int? {
        guard let s = scale?.split(separator: "x").first, let w = Int(s) else { return nil }
        return w
    }
}

/// What kind of in-process operation a `native` plan should run.
enum NativeKind {
    case imageIO(Format)
    case pdfFromImages
    case pdfRasterize(Format)
}

struct Invocation {
    var engine: EngineID
    var args: [String] = []          // excludes the resolved binary path
    var producesDirectory = false    // the output path is a directory to create
    var nativeKind: NativeKind? = nil
    var rasterizeInputToPGM = false  // write a temp PGM first; "{PGM}" in args is the temp path
}

protocol Converter {
    /// Formats this converter can produce from `input` (excluding `input` itself).
    func targets(for input: Format) -> [Format]
    func plan(input: URL, from: Format, to: Format, output: URL, opts: ConvertOptions) throws -> Invocation
}

enum ConvertError: LocalizedError {
    case badInput(String)
    case unsupported(from: String, to: String)
    case engineMissing(EngineID)
    case rarCreateUnsupported
    case processFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .badInput(let m): return m
        case .unsupported(let f, let t): return "No route from \(f.uppercased()) to \(t.uppercased())."
        case .engineMissing(let e):
            return "The \(e.rawValue) engine isn't installed. Run Scripts/bundle-engines.sh, "
                 + "or `brew install \(e == .sevenzip ? "sevenzip" : e.rawValue)`."
        case .rarCreateUnsupported:
            return "Creating RAR archives isn't supported — there's no licensable RAR encoder. Use ZIP or 7z."
        case .processFailed(let c, let m): return "Engine exited \(c): \(m)"
        }
    }
}

enum Engine {
    static let converters: [Converter] = [
        ImageConverter(),
        MediaConverter(),
        ArchiveConverter(),
        PDFConverter(),
    ]

    /// De-duplicated list of formats reachable from `input`, sorted by label.
    static func targets(for input: Format) -> [Format] {
        var seen: Set<String> = [input.id]
        var out: [Format] = []
        for c in converters {
            for t in c.targets(for: input) where !seen.contains(t.id) {
                seen.insert(t.id)
                out.append(t)
            }
        }
        return out.sorted { $0.label < $1.label }
    }

    static func converter(from: Format, to: Format) -> Converter? {
        converters.first { $0.targets(for: from).contains(to) }
    }

    /// Run a single file → single output conversion. Blocking; call off the main thread from the GUI.
    static func run(input: URL, to target: Format, output: URL, opts: ConvertOptions) throws {
        guard let from = Formats.byURL(input) else {
            throw ConvertError.badInput("Unrecognized file type: \(input.lastPathComponent)")
        }
        guard let conv = converter(from: from, to: target) else {
            throw ConvertError.unsupported(from: from.id, to: target.id)
        }
        let plan = try conv.plan(input: input, from: from, to: target, output: output, opts: opts)

        if plan.producesDirectory {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }

        if let kind = plan.nativeKind {
            try NativeOps.perform(kind, input: input, output: output, opts: opts)
            return
        }
        guard let bin = EngineLocator.path(for: plan.engine) else {
            throw ConvertError.engineMissing(plan.engine)
        }

        var args = plan.args
        var tmpPGM: URL?
        if plan.rasterizeInputToPGM {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kuori-\(UUID().uuidString).pgm")
            try NativeOps.writeGrayPGM(input, to: tmp)
            tmpPGM = tmp
            args = args.map { $0 == "{PGM}" ? tmp.path : $0 }
        }
        defer { if let t = tmpPGM { try? FileManager.default.removeItem(at: t) } }

        let r = ProcessRun.run(bin, args)
        if r.code != 0 {
            let msg = r.stderr.isEmpty ? r.stdout : r.stderr
            throw ConvertError.processFailed(code: r.code, message: String(msg.suffix(600)))
        }
    }
}
