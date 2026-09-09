import Foundation

/// An ordered pipeline of conversions and tools. Each step's output feeds the
/// next through a temp file; the last step writes beside the source (or into a
/// chosen folder). Built-ins ship in code; `recipes.json` merges over them.
struct RecipeStep: Codable {
    enum Kind: String, Codable { case convert, tool }
    var kind: Kind
    var to: String?            // convert: target format id
    var tool: String?          // tool: Tool.rawValue
    var quality: Int?
    var scale: String?         // convert scale, "WIDTHx"
    var strip: Bool?
    var scalePercent: Int?     // tool
    var maxEdge: Int?          // tool
    var aspect: String?        // tool
    var seconds: Double?       // tool (trim)
}

struct Recipe: Codable {
    var name: String
    var steps: [RecipeStep]
}

enum Recipes {
    static let builtins: [Recipe] = [
        Recipe(name: "web-image", steps: [
            RecipeStep(kind: .tool, tool: "resize", maxEdge: 1600),
            RecipeStep(kind: .tool, tool: "stripMetadata"),
            RecipeStep(kind: .convert, to: "webp", quality: 82),
        ]),
        Recipe(name: "square-jpg", steps: [
            RecipeStep(kind: .tool, tool: "crop", aspect: "1:1"),
            RecipeStep(kind: .tool, tool: "resize", maxEdge: 1080),
            RecipeStep(kind: .convert, to: "jpg", quality: 82),
        ]),
        Recipe(name: "reel-to-mp4", steps: [
            RecipeStep(kind: .tool, tool: "resize", maxEdge: 1280),
            RecipeStep(kind: .convert, to: "mp4", quality: 42),
        ]),
        Recipe(name: "clip-to-gif", steps: [
            RecipeStep(kind: .tool, tool: "trim", seconds: 6),
            RecipeStep(kind: .convert, to: "gif", scale: "480x"),
        ]),
        Recipe(name: "scan-to-ocr-pdf", steps: [
            RecipeStep(kind: .tool, tool: "ocr"),
        ]),
    ]

    static func all() -> [Recipe] {
        var byName = Dictionary(uniqueKeysWithValues: builtins.map { ($0.name, $0) })
        for r in Support.loadJSON([Recipe].self, from: "recipes.json") ?? [] { byName[r.name] = r }
        return byName.values.sorted { $0.name < $1.name }
    }

    static func named(_ n: String) -> Recipe? {
        all().first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    static func seedFileIfMissing() {
        if !FileManager.default.fileExists(atPath: Support.file("recipes.json").path) {
            Support.saveJSON(builtins, to: "recipes.json")
        }
    }
}

enum RecipeRunner {
    /// Run `recipe` over one input, returning the final output URL.
    @discardableResult
    static func run(_ recipe: Recipe, input: URL, into dir: URL?) throws -> URL {
        guard !recipe.steps.isEmpty else { throw ConvertError.badInput("Recipe '\(recipe.name)' has no steps.") }
        var current = input
        var temps: [URL] = []
        defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }

        for (i, step) in recipe.steps.enumerated() {
            let isLast = i == recipe.steps.count - 1
            guard let f = Formats.byURL(current) else {
                throw ConvertError.badInput("Step \(i + 1): unrecognized \(current.lastPathComponent)")
            }

            switch step.kind {
            case .convert:
                guard let id = step.to, let target = Formats.byID[id] else {
                    throw ConvertError.badInput("Step \(i + 1): missing target format")
                }
                let out = isLast
                    ? (Naming.output(for: input, target: target, into: dir, collision: .suffix)
                        ?? tmp(target.ext))
                    : tmp(target.ext)
                if !isLast { temps.append(out) }
                current = try Engine.run(input: current, to: target, output: out,
                                         opts: ConvertOptions(quality: step.quality, scale: step.scale,
                                                              stripMetadata: step.strip ?? false))

            case .tool:
                guard let raw = step.tool, let t = Tool(rawValue: raw) else {
                    throw ConvertError.badInput("Step \(i + 1): unknown tool '\(step.tool ?? "")'")
                }
                let ext = t.outputExt ?? (current.pathExtension.isEmpty ? f.ext : current.pathExtension)
                let out = isLast
                    ? (Naming.toolOutput(for: input, tag: t.rawValue, ext: ext, into: dir) ?? tmp(ext))
                    : tmp(ext)
                if !isLast { temps.append(out) }
                var p = ToolRunner.Params()
                p.quality = step.quality; p.scalePercent = step.scalePercent
                p.maxEdge = step.maxEdge; p.aspect = step.aspect; p.trimDuration = step.seconds
                try ToolRunner.apply(t, input: current, format: f, output: out, params: p)
                current = out
            }
        }
        return current
    }

    private static func tmp(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kuori-rcp-\(UUID().uuidString).\(ext)")
    }
}
