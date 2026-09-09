import Foundation

/// Resolves an `EngineID` to an executable path. Looks inside the app bundle
/// first, then Application Support, then `PATH` and the usual Homebrew prefixes
/// so it also works from `swift run` on a dev machine.
enum EngineLocator {
    static let binaryName: [EngineID: String] = [
        .ffmpeg: "ffmpeg", .vips: "vips", .cwebp: "cwebp", .resvg: "resvg", .potrace: "potrace",
        .pandoc: "pandoc", .qpdf: "qpdf", .sevenzip: "7zz", .unar: "unar",
        .bsdtar: "bsdtar", .exiftool: "exiftool", .libreoffice: "soffice",
    ]

    static var supportEngineDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Kuori/engine", isDirectory: true)
    }

    /// LibreOffice is bring-your-own — a normal /Applications install, or a copy
    /// dropped into Application Support. Never auto-downloaded (it's ~400 MB).
    static func libreOffice() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            supportEngineDir.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice").path,
            supportEngineDir.appendingPathComponent("soffice").path,
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    #if arch(arm64)
    private static let hostCPU: UInt32 = 0x0100_000C   // CPU_TYPE_ARM64
    #else
    private static let hostCPU: UInt32 = 0x0100_0007   // CPU_TYPE_X86_64
    #endif

    private static var archCache: [String: Bool] = [:]
    private static let archLock = NSLock()

    /// Does this Mach-O contain a slice for the arch we're running? Reads the
    /// header rather than shelling out to `lipo`, and remembers the answer.
    static func runnable(_ path: String) -> Bool {
        archLock.lock(); defer { archLock.unlock() }
        if let known = archCache[path] { return known }
        let answer = readArch(path)
        archCache[path] = answer
        return answer
    }

    private static func readArch(_ path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 4096), data.count >= 8 else { return false }
        let b = [UInt8](data)
        func be(_ o: Int) -> UInt32 {
            UInt32(b[o]) << 24 | UInt32(b[o+1]) << 16 | UInt32(b[o+2]) << 8 | UInt32(b[o+3])
        }
        func le(_ o: Int) -> UInt32 {
            UInt32(b[o+3]) << 24 | UInt32(b[o+2]) << 16 | UInt32(b[o+1]) << 8 | UInt32(b[o])
        }
        switch be(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:                  // fat: walk the slice table
            let wide = be(0) == 0xCAFE_BABF
            let stride = wide ? 32 : 20
            let count = Int(be(4))
            for i in 0..<min(count, 32) {
                let off = 8 + i * stride
                guard off + 4 <= b.count else { break }
                if be(off) == hostCPU { return true }
            }
            return false
        case 0xCFFA_EDFE, 0xCEFA_EDFE:                  // thin little-endian Mach-O
            return le(4) == hostCPU
        default:
            // Not a Mach-O (a shell or Perl script, say) — let the OS decide.
            return true
        }
    }

    static func path(for id: EngineID) -> String? {
        if id == .native { return nil }
        if id == .libreoffice { return libreOffice() }
        guard let name = binaryName[id] else { return nil }
        let fm = FileManager.default

        // A bundled engine is only usable if it was built for the arch we're
        // running. The bundle ships arm64 binaries, so on Intel we skip straight
        // past them to whatever is on PATH.
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("engine/\(name)").path
            if fm.isExecutableFile(atPath: bundled), runnable(bundled) { return bundled }
        }
        let support = supportEngineDir.appendingPathComponent(name).path
        if fm.isExecutableFile(atPath: support), runnable(support) { return support }

        // /opt/homebrew is the Apple Silicon prefix, /usr/local the Intel one —
        // both are searched, and the arch gate picks whichever can actually run.
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            dirs += envPath.split(separator: ":").map(String.init)
        }
        for d in dirs {
            let c = d + "/" + name
            if fm.isExecutableFile(atPath: c), runnable(c) { return c }
        }
        return nil
    }
}
