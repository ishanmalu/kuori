import Foundation

/// What a drop actually means.
///
/// A folder is ambiguous: it might be something to zip, or a batch of files to
/// convert. Rather than pick, `expand` returns both readings — the files to act
/// on, and the folder they came from when there was one — and the caller offers
/// both sets of targets.
enum InputSet {
    /// Files to convert, plus the folder they were expanded from.
    ///
    /// Shallow on purpose: a deep walk of a home directory would stall the drop,
    /// and nested output layout has no obvious right answer. A folder holding
    /// nothing convertible stays a folder, so it can still be archived.
    static func expand(_ urls: [URL]) -> (files: [URL], folder: URL?) {
        guard urls.count == 1, let dir = urls.first,
              Formats.byURL(dir)?.id == "folder" else { return (urls, nil) }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []

        let convertible = children
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .compactMap { url -> URL? in
                guard let f = Formats.byURL(url), !Engine.targets(for: f).isEmpty else { return nil }
                return url
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return convertible.isEmpty ? (urls, nil) : (convertible, dir)
    }
}
