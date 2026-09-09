import Foundation

/// A named conversion recipe-of-one: a target format plus options. Built-ins
/// ship in code; the user's `presets.json` is merged over them by name.
struct Preset: Codable, Equatable {
    var name: String
    var target: String        // format id
    var quality: Int?
    var scale: String?        // "WIDTHx"
    var strip: Bool = false

    var options: ConvertOptions {
        ConvertOptions(quality: quality, scale: scale, stripMetadata: strip)
    }
    var targetFormat: Format? { Formats.byID[target] }
}

enum Presets {
    static let builtins: [Preset] = [
        Preset(name: "web-jpg",  target: "jpg",  quality: 80, scale: "2000x", strip: true),
        Preset(name: "web-webp", target: "webp", quality: 80, scale: "2000x", strip: true),
        Preset(name: "thumb",    target: "jpg",  quality: 70, scale: "480x",  strip: true),
        Preset(name: "discord-video", target: "mp4", quality: 45, scale: "1280x"),
        Preset(name: "voice-mp3", target: "mp3", quality: 55),
        Preset(name: "archive-flac", target: "flac"),
    ]

    static func all() -> [Preset] {
        var byName = Dictionary(uniqueKeysWithValues: builtins.map { ($0.name, $0) })
        for p in Support.loadJSON([Preset].self, from: "presets.json") ?? [] { byName[p.name] = p }
        return byName.values.sorted { $0.name < $1.name }
    }

    static func named(_ n: String) -> Preset? {
        all().first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    /// Write the current effective list so the user has something to edit.
    static func seedFileIfMissing() {
        let f = Support.file("presets.json")
        if !FileManager.default.fileExists(atPath: f.path) { Support.saveJSON(builtins, to: "presets.json") }
    }
}
