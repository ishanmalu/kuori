import AppKit
import UniformTypeIdentifiers

/// The floating drop target. Drop files, then click a format tile to convert.
/// Shared targets across a multi-file drop are the intersection of each file's
/// routes, so a tile only appears if every dropped file can produce it.
final class DropPanel: NSPanel {
    static let shared = DropPanel()

    private let dropView = DropView()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = Theme.paper
        hidesOnDeactivate = false
        contentView = dropView
    }

    func toggle() { isVisible ? orderOut(nil) : showCentered() }

    func showCentered() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder Services / external drops.
    func load(urls: [URL]) {
        showCentered()
        dropView.accept(urls)
    }
}

// MARK: - Monochrome tile

private final class TileButton: NSButton {
    private var hot = false { didSet { needsDisplay = true } }

    init(_ format: Format, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        title = format.label
        identifier = NSUserInterfaceItemIdentifier(format.id)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Theme.tileWidth).isActive = true
        heightAnchor.constraint(equalToConstant: Theme.tileHeight).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hot = isEnabled }
    override func mouseExited(with event: NSEvent) { hot = false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: Theme.tileCorner, yRadius: Theme.tileCorner)
        if hot { Theme.ink.setFill(); path.fill() }
        Theme.hairline.setStroke(); path.lineWidth = 1; path.stroke()

        let color = hot ? Theme.paper : (isEnabled ? Theme.ink : Theme.inkFaint)
        let s = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ])
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }
}

// MARK: - Drop view

private final class DropView: NSView {
    private var inputs: [URL] = []
    private var dragging = false { didSet { needsDisplay = true } }
    private var populated = false { didSet { needsDisplay = true } }

    private let headline = DropView.label(15, .semibold)
    private let hint = DropView.label(11, .regular, faint: true)
    private let grid = NSStackView()
    private let status = DropView.label(11, .regular, faint: true)
    private let queue = DispatchQueue(label: "kuori.convert", qos: .userInitiated, attributes: .concurrent)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true

        headline.stringValue = "Drop files to convert"
        headline.alignment = .center
        hint.alignment = .center
        status.alignment = .center
        status.lineBreakMode = .byTruncatingMiddle
        grid.orientation = .vertical
        grid.alignment = .centerX
        grid.spacing = Theme.tileGap

        let stack = NSStackView(views: [headline, hint, grid, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Theme.pad),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.pad),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func label(_ size: CGFloat, _ weight: NSFont.Weight, faint: Bool = false) -> NSTextField {
        let t = NSTextField(labelWithString: "")
        t.font = .systemFont(ofSize: size, weight: weight)
        t.textColor = faint ? Theme.inkFaint : Theme.ink
        return t
    }

    // Paper fill + a border that reads as: idle (hairline dashed), armed (solid ink), populated (solid hairline).
    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill()
        bounds.fill()
        let r = bounds.insetBy(dx: Theme.pad * 0.5, dy: Theme.pad * 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: Theme.corner, yRadius: Theme.corner)
        path.lineWidth = dragging ? 2 : 1
        (dragging ? Theme.ink : Theme.hairline).setStroke()
        if !populated && !dragging { path.setLineDash([5, 4], count: 2, phase: 0) }
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    // drag

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragging = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragging = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragging = false
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return false }
        accept(urls)
        return true
    }

    func accept(_ urls: [URL]) {
        inputs = urls
        status.stringValue = ""
        headline.stringValue = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"

        let perFile = urls.map { url -> Set<String> in
            guard let f = Formats.byURL(url) else { return [] }
            return Set(Engine.targets(for: f).map(\.id))
        }
        let shared = perFile.dropFirst().reduce(perFile.first ?? []) { $0.intersection($1) }
        let targets = shared.compactMap { Formats.byID[$0] }
            .filter { $0.id != "folder" || urls.allSatisfy { Formats.byURL($0)?.category == .archive } }
            .sorted { $0.label < $1.label }

        rebuildGrid(with: targets)
        populated = !targets.isEmpty
        hint.stringValue = targets.isEmpty ? "nothing converts this whole selection" : "convert all to"
    }

    private func rebuildGrid(with targets: [Format]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row = newRow()
        for (i, fmt) in targets.enumerated() {
            if i > 0 && i % 4 == 0 { grid.addArrangedSubview(row); row = newRow() }
            row.addArrangedSubview(TileButton(fmt, target: self, action: #selector(tileClicked(_:))))
        }
        if !row.arrangedSubviews.isEmpty { grid.addArrangedSubview(row) }
    }

    private func newRow() -> NSStackView {
        let r = NSStackView()
        r.orientation = .horizontal
        r.spacing = Theme.tileGap
        return r
    }

    private func allTiles() -> [TileButton] {
        grid.arrangedSubviews.flatMap { ($0 as? NSStackView)?.arrangedSubviews ?? [] }.compactMap { $0 as? TileButton }
    }

    @objc private func tileClicked(_ sender: TileButton) {
        guard let id = sender.identifier?.rawValue, let target = Formats.byID[id] else { return }
        let files = inputs
        guard !files.isEmpty else { return }
        allTiles().forEach { $0.isEnabled = false }

        let group = DispatchGroup()
        let lock = NSLock()
        var done = 0, failed = 0
        var firstOutput: URL?

        for input in files {
            guard let output = Naming.output(for: input, target: target, into: nil, collision: .suffix) else { continue }
            lock.lock(); if firstOutput == nil { firstOutput = output }; lock.unlock()
            group.enter()
            queue.async {
                var ok = true
                do { try Engine.run(input: input, to: target, output: output, opts: ConvertOptions()) }
                catch {
                    ok = false
                    DispatchQueue.main.async { self.status.stringValue = error.localizedDescription }
                }
                lock.lock(); if ok { done += 1 } else { failed += 1 }; let d = done, f = failed; lock.unlock()
                if f == 0 { DispatchQueue.main.async { self.status.stringValue = "converting \(d) of \(files.count)" } }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.allTiles().forEach { $0.isEnabled = true }
            if failed == 0 {
                self.status.stringValue = "done — \(done) file\(done == 1 ? "" : "s") to \(target.label)"
                if let out = firstOutput { NSWorkspace.shared.activateFileViewerSelecting([out]) }
            } else {
                self.status.stringValue = "\(done) ok, \(failed) failed"
            }
        }
    }
}
