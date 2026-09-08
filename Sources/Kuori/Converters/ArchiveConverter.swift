import Foundation

/// Folder ⇄ archive. Extraction goes through `bsdtar` (libarchive reads zip,
/// tar.*, 7z, and RARv5). Creation covers zip/tar/tar.gz via bsdtar and 7z via
/// the bundled `7zz`. Archive→archive repacking is Phase 2.
struct ArchiveConverter: Converter {
    static let creatable = ["zip", "tar", "targz", "7z"]

    func targets(for input: Format) -> [Format] {
        if input.id == "folder" {
            return Self.creatable.compactMap { Formats.byID[$0] }
        }
        if input.category == .archive {
            return [Formats.byID["folder"]!]
        }
        return []
    }

    func plan(input: URL, from: Format, to: Format, output: URL, opts: ConvertOptions) throws -> Invocation {
        if to.id == "rar" { throw ConvertError.rarCreateUnsupported }

        // folder → archive
        if from.id == "folder" {
            let parent = input.deletingLastPathComponent().path
            let name = input.lastPathComponent
            switch to.id {
            case "zip":   return Invocation(engine: .bsdtar, args: ["-a", "-c", "-f", output.path, "-C", parent, name])
            case "tar":   return Invocation(engine: .bsdtar, args: ["-c", "-f", output.path, "-C", parent, name])
            case "targz": return Invocation(engine: .bsdtar, args: ["-c", "-z", "-f", output.path, "-C", parent, name])
            case "7z":    return Invocation(engine: .sevenzip, args: ["a", "-t7z", "-bd", output.path, input.path])
            default: throw ConvertError.unsupported(from: from.id, to: to.id)
            }
        }

        // archive → folder (extract)
        if to.id == "folder" {
            return Invocation(engine: .bsdtar,
                              args: ["-x", "-f", input.path, "-C", output.path],
                              producesDirectory: true)
        }

        throw ConvertError.unsupported(from: from.id, to: to.id)
    }
}
