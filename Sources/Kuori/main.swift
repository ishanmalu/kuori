import AppKit

let rawArgs = Array(CommandLine.arguments.dropFirst())

if rawArgs.first == "--selftest" {
    SelfTest.run()
}

// CLI mode: anything that starts with a known verb runs headless and exits.
if let first = rawArgs.first,
   ["convert", "tool", "merge", "split", "recipe", "watch", "presets", "recipes",
    "formats", "info", "help", "-h", "--help"].contains(first) {
    exit(CLI.run(rawArgs))
}

// `--shot-ui <out.png> [dark]` renders the drop panel to a file and exits.
// Used to eyeball the UI without a human at the keyboard.
if let i = rawArgs.firstIndex(of: "--shot-ui") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let out = rawArgs.indices.contains(i + 1) ? rawArgs[i + 1] : "panel.png"
    app.appearance = NSAppearance(named: rawArgs.contains("dark") ? .darkAqua : .aqua)
    let panel = DropPanel.shared
    panel.showCentered()
    panel.load(urls: [URL(fileURLWithPath: "/tmp/holiday.png"),
                      URL(fileURLWithPath: "/tmp/logo.jpg")])
    if rawArgs.contains("tools") { panel.previewMode("tools") }
    if rawArgs.contains("recipes") { panel.previewMode("recipes") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        guard let view = panel.contentView else { exit(1) }
        view.layoutSubtreeIfNeeded()
        if let ap = app.appearance { view.appearance = ap }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        exit(0)
    }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
