import Foundation

enum Collision: String {
    case suffix     // "name 2.ext", "name 3.ext", ...
    case overwrite
    case skip
}

enum Naming {
    /// Where a conversion of `input` to `target` should be written.
    /// `dir == nil` means "beside the source". Returns nil only when the policy
    /// is `.skip` and something is already there.
    static func output(for input: URL, target: Format, into dir: URL?, collision: Collision) -> URL? {
        let fm = FileManager.default
        let baseDir = dir ?? input.deletingLastPathComponent()
        let stem = strippedStem(of: input)

        func candidate(_ suffix: String) -> URL {
            let name = suffix.isEmpty ? stem : "\(stem) \(suffix)"
            return target.ext.isEmpty
                ? baseDir.appendingPathComponent(name, isDirectory: true)
                : baseDir.appendingPathComponent(name).appendingPathExtension(target.ext)
        }

        var url = candidate("")
        if url.path == input.path { url = candidate("converted") }

        guard fm.fileExists(atPath: url.path) else { return url }
        switch collision {
        case .overwrite: return url
        case .skip:      return nil
        case .suffix:
            var n = 2
            while fm.fileExists(atPath: candidate(String(n)).path) { n += 1 }
            return candidate(String(n))
        }
    }

    /// Drop the extension, collapsing the `.tar.gz` / `.tgz` double extension.
    static func strippedStem(of url: URL) -> String {
        let name = url.lastPathComponent
        if name.lowercased().hasSuffix(".tar.gz") { return String(name.dropLast(7)) }
        return url.deletingPathExtension().lastPathComponent
    }
}
