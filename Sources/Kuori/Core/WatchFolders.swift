import Foundation
import CoreServices

/// Auto-converts whatever lands in a watched folder, then moves the original to
/// `<folder>/_processed/`. In-process; rules persist in `watch.json`.
struct WatchRule: Codable {
    var folder: String
    var toFormat: String?      // convert target id — mutually exclusive with recipe
    var recipe: String?        // recipe name
    var quality: Int?
    var enabled: Bool = true
}

final class WatchFolders {
    static let shared = WatchFolders()

    private let lock = NSLock()
    private var _rules: [WatchRule] = []
    private var stream: FSEventStreamRef?
    private let workQueue = DispatchQueue(label: "kuori.watch", qos: .utility)
    private var inFlight = Set<String>()

    /// A snapshot; the FSEvents callback and the Settings UI both touch this.
    var rules: [WatchRule] {
        lock.lock(); defer { lock.unlock() }
        return _rules
    }
    private func setRules(_ r: [WatchRule]) {
        lock.lock(); _rules = r; lock.unlock()
    }

    func load() { setRules(Support.loadJSON([WatchRule].self, from: "watch.json") ?? []) }
    func save() { Support.saveJSON(rules, to: "watch.json") }

    func add(_ r: WatchRule) { setRules(rules + [r]); save(); restart() }
    func remove(at i: Int) {
        var r = rules; guard r.indices.contains(i) else { return }
        r.remove(at: i); setRules(r); save(); restart()
    }
    func setEnabled(_ on: Bool, at i: Int) {
        var r = rules; guard r.indices.contains(i) else { return }
        r[i].enabled = on; setRules(r); save(); restart()
    }

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

    /// One-shot: handle whatever is already sitting in the watched folders.
    func sweepAll() {
        for rule in rules where rule.enabled {
            let dir = URL(fileURLWithPath: rule.folder)
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in items where f.lastPathComponent != "_processed" && !f.hasDirectoryPath {
                process(f, rule: rule)
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
        // give the writer a second to finish
        workQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.process(url, rule: rule) }
    }

    private func claim(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.insert(key).inserted
    }
    private func release(_ key: String) {
        lock.lock(); inFlight.remove(key); lock.unlock()
    }

    private func process(_ file: URL, rule: WatchRule) {
        let key = file.path
        guard FileManager.default.fileExists(atPath: key), claim(key) else { return }
        defer { release(key) }

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
