import Foundation

/// The file kinds Daisy knows how to move between. Everything the UI and CLI
/// offer is derived from this table plus the capability graph in `Engine.swift`.
enum Category: String, CaseIterable {
    case image, video, audio, document, archive
}

struct Format: Hashable {
    let id: String        // canonical token, e.g. "jpg"
    let ext: String       // extension written to disk, e.g. "jpg" ("tar.gz" for targz, "" for folder)
    let category: Category

    var label: String {
        switch id {
        case "targz": return "TAR.GZ"
        case "folder": return "Folder"
        default: return id.uppercased()
        }
    }
}

enum Formats {
    static let list: [Format] = [
        // image
        Format(id: "jpg",  ext: "jpg",  category: .image),
        Format(id: "png",  ext: "png",  category: .image),
        Format(id: "webp", ext: "webp", category: .image),
        Format(id: "heic", ext: "heic", category: .image),
        Format(id: "avif", ext: "avif", category: .image),
        Format(id: "tiff", ext: "tiff", category: .image),
        Format(id: "bmp",  ext: "bmp",  category: .image),
        Format(id: "gif",  ext: "gif",  category: .image),
        Format(id: "svg",  ext: "svg",  category: .image),
        // video
        Format(id: "mp4",  ext: "mp4",  category: .video),
        Format(id: "mov",  ext: "mov",  category: .video),
        Format(id: "mkv",  ext: "mkv",  category: .video),
        Format(id: "webm", ext: "webm", category: .video),
        Format(id: "avi",  ext: "avi",  category: .video),
        Format(id: "m4v",  ext: "m4v",  category: .video),
        // audio
        Format(id: "mp3",  ext: "mp3",  category: .audio),
        Format(id: "m4a",  ext: "m4a",  category: .audio),
        Format(id: "aac",  ext: "aac",  category: .audio),
        Format(id: "wav",  ext: "wav",  category: .audio),
        Format(id: "flac", ext: "flac", category: .audio),
        Format(id: "ogg",  ext: "ogg",  category: .audio),
        Format(id: "opus", ext: "opus", category: .audio),
        Format(id: "aiff", ext: "aiff", category: .audio),
        // document
        Format(id: "pdf",  ext: "pdf",  category: .document),
        Format(id: "docx", ext: "docx", category: .document),
        Format(id: "odt",  ext: "odt",  category: .document),
        Format(id: "rtf",  ext: "rtf",  category: .document),
        Format(id: "txt",  ext: "txt",  category: .document),
        Format(id: "md",   ext: "md",   category: .document),
        Format(id: "html", ext: "html", category: .document),
        Format(id: "epub", ext: "epub", category: .document),
        Format(id: "pptx", ext: "pptx", category: .document),
        Format(id: "xlsx", ext: "xlsx", category: .document),
        Format(id: "odp",  ext: "odp",  category: .document),
        Format(id: "ods",  ext: "ods",  category: .document),
        // archive (+ the "folder" pseudo-format used as an extraction target / compression source)
        Format(id: "zip",    ext: "zip",    category: .archive),
        Format(id: "tar",    ext: "tar",    category: .archive),
        Format(id: "targz",  ext: "tar.gz", category: .archive),
        Format(id: "7z",     ext: "7z",     category: .archive),
        Format(id: "rar",    ext: "rar",    category: .archive),
        Format(id: "folder", ext: "",       category: .archive),
    ]

    static let byID: [String: Format] = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

    /// Extra extensions that map onto a canonical format id.
    static let aliases: [String: String] = [
        "jpeg": "jpg", "jpe": "jpg", "jfif": "jpg",
        "tif": "tiff", "heif": "heic",
        "qt": "mov", "mpeg4": "mp4",
        "markdown": "md", "mdown": "md", "htm": "html", "text": "txt",
        "tgz": "targz",
    ]

    static func byExtension(_ raw: String) -> Format? {
        let e = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if let f = byID[e] { return f }
        if let canon = aliases[e], let f = byID[canon] { return f }
        return nil
    }

    /// Resolve a path to a format. Directories resolve to `folder`; `.tar.gz`
    /// and `.tgz` collapse to `targz` before the plain-extension lookup.
    static func byURL(_ url: URL) -> Format? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return byID["folder"]
        }
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return byID["targz"] }
        return byExtension(url.pathExtension)
    }
}
