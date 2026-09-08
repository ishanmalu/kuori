import Foundation

/// Resolves an `EngineID` to an absolute executable path.
///
/// Order: binary bundled inside `Kuori.app/Contents/Resources/engine/`, then an
/// on-demand engine under Application Support (LibreOffice is fetched there on
/// first use), then `PATH` and the usual Homebrew prefixes for dev machines.
enum EngineLocator {
    static let binaryName: [EngineID: String] = [
        .ffmpeg: "ffmpeg", .vips: "vips", .resvg: "resvg", .potrace: "potrace",
        .pandoc: "pandoc", .qpdf: "qpdf", .sevenzip: "7zz", .unar: "unar",
        .bsdtar: "bsdtar", .exiftool: "exiftool", .libreoffice: "soffice",
    ]

    static var supportEngineDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Kuori/engine", isDirectory: true)
    }

    /// LibreOffice is bring-your-own: a normal install under /Applications, or an
    /// unpacked copy dropped into Application Support. We never auto-download a
    /// ~400 MB payload.
    static func libreOffice() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            supportEngineDir.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice").path,
            supportEngineDir.appendingPathComponent("soffice").path,
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    static func path(for id: EngineID) -> String? {
        if id == .native { return nil }
        if id == .libreoffice { return libreOffice() }
        guard let name = binaryName[id] else { return nil }
        let fm = FileManager.default

        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("engine/\(name)").path
            if fm.isExecutableFile(atPath: bundled) { return bundled }
        }
        let support = supportEngineDir.appendingPathComponent(name).path
        if fm.isExecutableFile(atPath: support) { return support }

        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            dirs += envPath.split(separator: ":").map(String.init)
        }
        for d in dirs {
            let c = d + "/" + name
            if fm.isExecutableFile(atPath: c) { return c }
        }
        return nil
    }

    /// ffprobe always lives beside the ffmpeg we resolved.
    static func ffprobe() -> String? {
        guard let ff = path(for: .ffmpeg) else { return nil }
        let sib = (ff as NSString).deletingLastPathComponent + "/ffprobe"
        return FileManager.default.isExecutableFile(atPath: sib) ? sib : nil
    }

    static func isAvailable(_ id: EngineID) -> Bool {
        id == .native || path(for: id) != nil
    }
}
