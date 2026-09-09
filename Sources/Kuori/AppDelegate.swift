import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Presets.seedFileIfMissing()
        Recipes.seedFileIfMissing()
        WatchFolders.shared.load()
        WatchFolders.shared.start()
        DragMonitor.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Wheel", action: #selector(openDropZone), keyEquivalent: "d")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(withTitle: "Kuori \(ver)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Quit Kuori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openDropZone() { DropPanel.shared.toggle() }
    @objc private func openSettings() { SettingsWindow.shared.show() }

    /// Finder → Services → "Convert with Kuori…"
    @objc func convertFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty else { return }
        DropPanel.shared.load(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DropPanel.shared.showCentered()
        return true
    }

    /// A peel curl — the app icon reduced to a monochrome template stroke so the
    /// menu bar tints it for light/dark automatically.
    private static func menuBarIcon() -> NSImage {
        let d: CGFloat = 18
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        let c = CGPoint(x: d / 2, y: d / 2)
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        let turns = 1.15, thetaMax = turns * 2 * .pi
        let rOuter = d * 0.40, rInner = d * 0.10
        let steps = 120
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let theta = CGFloat(thetaMax) * t
            let r = rOuter - (rOuter - rInner) * t
            let p = CGPoint(x: c.x + cos(theta) * r, y: c.y + sin(theta) * r)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        NSColor.black.setStroke()
        path.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
