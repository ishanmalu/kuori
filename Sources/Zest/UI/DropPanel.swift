import AppKit
import UniformTypeIdentifiers

/// The floating drop target. Drop files, then click a format tile to convert.
/// Shared targets across a multi-file drop are the intersection of each file's
/// routes, so a tile only appears if every dropped file can produce it.
final class DropPanel: NSPanel {
    static let shared = DropPanel()

    private let dropView = DropView()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .windowBackgroundColor
        hidesOnDeactivate = false
        contentView = dropView
    }

    func toggle() {
        if isVisible { orderOut(nil) }
        else { showCentered() }
    }

    func showCentered() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called by the Services handler / external drops.
    func load(urls: [URL]) {
        showCentered()
        dropView.accept(urls)
    }
}

// MARK: - Drop view

private final class DropView: NSView {
    private var inputs: [URL] = []
    private let headline = NSTextField(labelWithString: "Drop files to convert")
    private let subline = NSTextField(labelWithString: "images · video · audio · documents · archives")
    private let grid = NSStackView()
    private let status = NSTextField(labelWithString: "")
    private let queue = DispatchQueue(label: "zest.convert", qos: .userInitiated, attributes: .concurrent)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true

        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        headline.alignment = .center
        subline.font = .systemFont(ofSize: 11)
        subline.textColor = .secondaryLabelColor
        subline.alignment = .center
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.lineBreakMode = .byTruncatingMiddle

        grid.orientation = .vertical
        grid.alignment = .centerX
        grid.spacing = Theme.tileGap

        let stack = NSStackView(views: [headline, subline, grid, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
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

    // drag

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return false }
        accept(urls)
        return true
    }

    func accept(_ urls: [URL]) {
        inputs = urls
        status.stringValue = ""
        headline.stringValue = urls.count == 1
            ? urls[0].lastPathComponent
            : "\(urls.count) files"

        let perFile = urls.map { url -> Set<String> in
            guard let f = Formats.byURL(url) else { return [] }
            return Set(Engine.targets(for: f).map(\.id))
        }
        let shared = perFile.dropFirst().reduce(perFile.first ?? []) { $0.intersection($1) }
        let targets = shared.compactMap { Formats.byID[$0] }
            .filter { $0.id != "folder" || urls.allSatisfy { Formats.byURL($0)?.category == .archive } }
            .sorted { $0.label < $1.label }

        rebuildGrid(with: targets)
        subline.stringValue = targets.isEmpty ? "no shared conversion for this selection"
                                              : "convert all to…"
    }

    private func rebuildGrid(with targets: [Format]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row = makeRow()
        for (i, fmt) in targets.enumerated() {
            if i > 0 && i % 4 == 0 { grid.addArrangedSubview(row); row = makeRow() }
            row.addArrangedSubview(makeTile(fmt))
        }
        if !row.arrangedSubviews.isEmpty { grid.addArrangedSubview(row) }
    }

    private func makeRow() -> NSStackView {
        let r = NSStackView()
        r.orientation = .horizontal
        r.spacing = Theme.tileGap
        return r
    }

    private func makeTile(_ fmt: Format) -> NSButton {
        let b = NSButton(title: fmt.label, target: self, action: #selector(tileClicked(_:)))
        b.bezelStyle = .rounded
        b.identifier = NSUserInterfaceItemIdentifier(fmt.id)
        b.contentTintColor = Theme.categoryTint(fmt.category)
        b.widthAnchor.constraint(equalToConstant: 78).isActive = true
        return b
    }

    @objc private func tileClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let target = Formats.byID[id] else { return }
        let files = inputs
        guard !files.isEmpty else { return }
        grid.arrangedSubviews.forEach { ($0 as? NSStackView)?.arrangedSubviews.forEach { ($0 as? NSButton)?.isEnabled = false } }

        let group = DispatchGroup()
        let lock = NSLock()
        var done = 0, failed = 0

        for input in files {
            guard let output = Naming.output(for: input, target: target, into: nil, collision: .suffix) else { continue }
            group.enter()
            queue.async {
                var ok = true
                do { try Engine.run(input: input, to: target, output: output, opts: ConvertOptions()) }
                catch {
                    ok = false
                    DispatchQueue.main.async { self.status.stringValue = error.localizedDescription }
                }
                lock.lock(); if ok { done += 1 } else { failed += 1 }; let d = done, f = failed; lock.unlock()
                DispatchQueue.main.async {
                    if f == 0 { self.status.stringValue = "converted \(d)/\(files.count)…" }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.grid.arrangedSubviews.forEach { ($0 as? NSStackView)?.arrangedSubviews.forEach { ($0 as? NSButton)?.isEnabled = true } }
            if failed == 0 {
                self.status.stringValue = "done — \(done) file\(done == 1 ? "" : "s") → \(target.label)"
                if let first = files.first,
                   let out = Naming.output(for: first, target: target, into: nil, collision: .overwrite) {
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                }
            } else {
                self.status.stringValue = "\(done) ok, \(failed) failed — see above"
            }
        }
    }
}
