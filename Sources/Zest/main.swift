import AppKit

let rawArgs = Array(CommandLine.arguments.dropFirst())

if rawArgs.first == "--selftest" {
    SelfTest.run()
}

// CLI mode: anything that starts with a known verb runs headless and exits.
if let first = rawArgs.first, ["convert", "formats", "info", "help", "-h", "--help"].contains(first) {
    exit(CLI.run(rawArgs))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
