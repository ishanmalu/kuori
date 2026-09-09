import AppKit

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--selftest" {
    SelfTest.run()
}

let cliVerbs: Set<String> = [
    "convert", "tool", "merge", "split", "recipe", "watch",
    "presets", "recipes", "formats", "info", "help", "-h", "--help",
]
if let verb = args.first, cliVerbs.contains(verb) {
    exit(CLI.run(args))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// `--shot-ui <out.png> [dark] [tools|recipes]` renders the wheel to a file and quits.
if let i = args.firstIndex(of: "--shot-ui") {
    let out = args.indices.contains(i + 1) ? args[i + 1] : "wheel.png"
    app.appearance = NSAppearance(named: args.contains("dark") ? .darkAqua : .aqua)
    let panel = DropPanel.shared
    panel.showCentered()
    panel.load(urls: [URL(fileURLWithPath: "/tmp/holiday.png"),
                      URL(fileURLWithPath: "/tmp/logo.jpg")])
    if args.contains("tools") { panel.previewMode("tools") }
    if args.contains("recipes") { panel.previewMode("recipes") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.layoutSubtreeIfNeeded()
        view.appearance = app.appearance
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        exit(0)
    }
    app.run()
}

// `--show <files…>` opens the wheel live and stays up.
if let i = args.firstIndex(of: "--show") {
    let paths = Array(args[(i + 1)...])
    let urls = paths.isEmpty ? [URL(fileURLWithPath: "/tmp/a.png")] : paths.map { URL(fileURLWithPath: $0) }
    DispatchQueue.main.async { DropPanel.shared.load(urls: urls) }
    app.run()
}

app.run()
