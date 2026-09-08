import Foundation

/// `Kuori convert …`, `Kuori formats`, `Kuori info <file>`. Shares the exact
/// conversion path the GUI uses, so anything the app can do is scriptable.
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        guard let cmd = args.first else { usage(); return 2 }
        switch cmd {
        case "formats":            return formats()
        case "info":               return info(Array(args.dropFirst()))
        case "convert":            return convert(Array(args.dropFirst()))
        case "-h", "--help", "help": usage(); return 0
        default:
            err("unknown command: \(cmd)")
            usage()
            return 2
        }
    }

    // MARK: convert

    private static func convert(_ args: [String]) -> Int32 {
        var inputs: [URL] = []
        var toID: String?
        var outDir: URL?
        var explicitOut: URL?
        var opts = ConvertOptions()
        var collision = Collision.suffix

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--to", "-t":
                i += 1; toID = i < args.count ? args[i] : nil
            case "--out", "-o":
                i += 1
                if i < args.count { outDir = URL(fileURLWithPath: args[i], isDirectory: true) }
            case "--quality", "-q":
                i += 1; opts.quality = i < args.count ? Int(args[i]) : nil
            case "--scale", "-s":
                i += 1; opts.scale = i < args.count ? args[i] : nil
            case "--strip":       opts.stripMetadata = true
            case "--overwrite":   collision = .overwrite
            case "--skip-existing": collision = .skip
            default:
                inputs.append(URL(fileURLWithPath: a))
            }
            i += 1
        }

        // Two-positional form with no --to: `kuori convert in.png out.webp`
        if toID == nil, inputs.count == 2,
           let outFmt = Formats.byURL(inputs[1]) ?? Formats.byExtension(inputs[1].pathExtension),
           !FileManager.default.fileExists(atPath: inputs[1].path) {
            explicitOut = inputs.removeLast()
            toID = outFmt.id
        }

        guard !inputs.isEmpty else { err("no input files"); return 2 }
        guard let toID, let target = Formats.byExtension(toID) ?? Formats.byID[toID] else {
            err("missing or unknown --to format"); return 2
        }

        var failures = 0
        for input in inputs {
            guard FileManager.default.fileExists(atPath: input.path) else {
                err("not found: \(input.path)"); failures += 1; continue
            }
            let output = explicitOut
                ?? Naming.output(for: input, target: target, into: outDir, collision: collision)
            guard let output else {
                print("skip  \(input.lastPathComponent) (exists)"); continue
            }
            do {
                try Engine.run(input: input, to: target, output: output, opts: opts)
                print("ok    \(input.lastPathComponent)  ->  \(output.path)")
            } catch {
                err("fail  \(input.lastPathComponent): \(error.localizedDescription)")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: formats / info

    private static func formats() -> Int32 {
        for cat in Category.allCases {
            let fs = Formats.list.filter { $0.category == cat && $0.id != "folder" }
            print("\n\(cat.rawValue.uppercased())")
            for f in fs {
                let outs = Engine.targets(for: f).map(\.label).joined(separator: " ")
                print("  \(f.label.padding(toLength: 8, withPad: " ", startingAt: 0)) -> \(outs)")
            }
        }
        return 0
    }

    private static func info(_ args: [String]) -> Int32 {
        guard let path = args.first else { err("usage: kuori info <file>"); return 2 }
        let url = URL(fileURLWithPath: path)
        guard let f = Formats.byURL(url) else { err("unrecognized: \(path)"); return 1 }
        print("\(url.lastPathComponent)")
        print("  format   \(f.label)  (\(f.category.rawValue))")
        print("  convert  \(Engine.targets(for: f).map(\.label).joined(separator: ", "))")
        return 0
    }

    private static func usage() {
        print("""
        Kuori — local file converter

          kuori convert <files…> --to <format> [--out <dir>] [--quality 1-100]
                       [--scale WxH] [--strip] [--overwrite | --skip-existing]
          kuori convert <in> <out>          two-file form, target inferred from <out>
          kuori formats                     what converts to what
          kuori info <file>                 identify a file and its routes
        """)
    }

    private static func err(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}
