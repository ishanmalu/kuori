import Foundation
import CoreServices

/// Auto-convert anything that lands in a watched folder, then move the original
/// into `<folder>/_processed/`. Runs in-process (the app is a login item). Rules
/// persist in `watch.json`.
struct WatchRule: Codable {
    var folder: String
    var toFormat: String?      // convert target id  (mutually exclusive with recipe)
    var recipe: String?        // recipe name
    var quality: Int?
    var enabled: Bool = true
}

final class WatchFolders {
    static let shared = WatchFolders()

    private(set) var rules: [WatchRule] = []
    private var stream: FSEventStreamRef?
    private let workQueue = DispatchQueue(label: "kuori.watch", qos: .utility)
    private var inFlight = Set<String>()

    func load() {
        rules = Support.loadJSON([WatchRule].self, from: "watch.json") ?? []
    }
    func save() { Support.saveJSON(rules, to: "watch.json") }

    func add(_ r: WatchRule) { rules.append(r); save(); restart() }
    func remove(at i: Int) { guard rules.indices.contains(i) else { return }; rules.remove(at: i); save(); restart() }
    func setEnabled(_ on: Bool, at i: Int) { guard rules.indices.contains(i) else { return }; rules[i].enabled = on; save(); restart() }

    func restart() { stop(); start() }

    func start() {
        let dirs = rules.filter(\.enabled).map(\.folder)
        guard !dirs.isEmpty else { return }
        for d in dirs {
            try? FileManager.default.createDirectory(atPath: (d as NSString).appendingPathComponent("_processed"),
                                                     withIntermediateDirectories: true)
        }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<WatchFolders>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            me.workQueue.async { arr.forEach(me.handle) }
        }
        stream = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx, dirs as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, workQueue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    /// One-shot: process everything already sitting in the watched folders.
    func sweepAll() {
        for (i, rule) in rules.enumerated() where rule.enabled {
            let dir = URL(fileURLWithPath: rule.folder)
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in items where f.lastPathComponent != "_processed" && !f.hasDirectoryPath {
                process(f, rule: rules[i])
            }
        }
    }

    // MARK: internals

    private func handle(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard !path.contains("/_processed/"), FileManager.default.fileExists(atPath: path),
              !url.hasDirectoryPath, url.lastPathComponent.first != "." else { return }
        guard let rule = rules.first(where: { $0.enabled && path.hasPrefix($0.folder + "/") }),
              (path as NSString).deletingLastPathComponent == rule.folder else { return }
        // debounce: let the file finish writing
        workQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.process(url, rule: rule) }
    }

    private func process(_ file: URL, rule: WatchRule) {
        let key = file.path
        guard !inFlight.contains(key), FileManager.default.fileExists(atPath: key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            if let recipeName = rule.recipe, let recipe = Recipes.named(recipeName) {
                _ = try RecipeRunner.run(recipe, input: file, into: nil)
            } else if let id = rule.toFormat, let target = Formats.byID[id] {
                guard let out = Naming.output(for: file, target: target, into: nil, collision: .suffix) else { return }
                try Engine.run(input: file, to: target, output: out,
                               opts: ConvertOptions(quality: rule.quality))
            } else { return }

            let processed = URL(fileURLWithPath: rule.folder)
                .appendingPathComponent("_processed").appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: processed)
            try? FileManager.default.moveItem(at: file, to: processed)
        } catch {
            NSLog("Kuori watch: \(file.lastPathComponent) — \(error.localizedDescription)")
        }
    }
}
