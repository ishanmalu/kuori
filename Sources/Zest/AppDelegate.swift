import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.left.arrow.right.square",
                                   accessibilityDescription: "Zest")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Drop Zone", action: #selector(openDropZone), keyEquivalent: "d")
        menu.addItem(.separator())
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(withTitle: "Zest \(ver)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Quit Zest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openDropZone() {
        DropPanel.shared.toggle()
    }

    /// Finder → Services → "Convert with Zest…"
    @objc func convertFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty else { return }
        DropPanel.shared.load(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DropPanel.shared.showCentered()
        return true
    }
}
