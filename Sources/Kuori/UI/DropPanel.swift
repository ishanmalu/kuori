import AppKit
import UniformTypeIdentifiers

/// The floating HUD. Drop files, then pick a format (Convert) or an edit
/// (Tools, held with ⌥ or toggled with Tab). Fully keyboard-drivable:
/// arrows move, ↵ runs, esc closes.
final class DropPanel: NSPanel {
    static let shared = DropPanel()

    private let hud = HUDView()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = hud
        hud.owner = self
    }

    override var canBecomeKey: Bool { true }

    func toggle() { isVisible ? orderOut(nil) : showCentered() }

    func showCentered() {
        fitToContent()
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2 + 40))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(hud)
    }

    func load(urls: [URL]) {
        showCentered()
        hud.accept(urls)
    }

    func fitToContent() {
        hud.layoutSubtreeIfNeeded()
        setContentSize(hud.fittingSize)
    }

    /// Used only by `--shot-ui` to render a non-default mode headlessly.
    func previewMode(_ name: String) { hud.forceMode(name) }
}

// MARK: - Chip

private final class Chip: NSView {
    enum Kind { case format(Format), tool(Tool), preset(Tool, ToolPreset), plain }
    let kind: Kind
    let title: String
    var onActivate: () -> Void = {}

    var gridRow = 0, gridCol = 0
    var enabled = true { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var focused = false { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }

    init(_ kind: Kind, title: String) {
        self.kind = kind
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Theme.tileHeight).isActive = true
        let w = title.size(withAttributes: [.font: Chip.font]).width + 24
        widthAnchor.constraint(equalToConstant: max(Theme.tileWidth, ceil(w))).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovered = enabled }
    override func mouseExited(with e: NSEvent) { hovered = false }
    override func mouseDown(with e: NSEvent) { if enabled { onActivate() } }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let fill = selected || hovered
        let path = NSBezierPath(roundedRect: r, xRadius: Theme.tileCorner, yRadius: Theme.tileCorner)
        if fill { Theme.ink.setFill(); path.fill() }
        (focused ? Theme.ink : Theme.hairline).setStroke()
        path.lineWidth = focused ? 2 : 1
        path.stroke()

        let color = fill ? Theme.paper : (enabled ? Theme.ink : Theme.inkFaint)
        let s = NSAttributedString(string: title, attributes: [.font: Chip.font, .foregroundColor: color])
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2 - 0.5))
    }
}

// MARK: - HUD

private final class HUDView: NSView {
    weak var owner: DropPanel?

    private enum Mode: CaseIterable { case convert, tools, recipes }
    private var mode: Mode = .convert { didSet { if oldValue != mode { rebuild() } } }
    private var optionHeld = false
    private var stickyMode: Mode?

    private var inputs: [URL] = []
    private var formats: [Format] = []
    private var selectedTool: Tool?
    private var running = false
    private var progress: Double = 0 {
        didSet { progressBar.fraction = progress; progressBar.needsDisplay = true }
    }

    private let title = HUDView.text(13, .semibold)
    private let sub = HUDView.text(11, .regular, faint: true)
    private let modePill = HUDView.text(10, .semibold, faint: true)
    private let footer = HUDView.text(10, .regular, faint: true)
    private let progressBar = ProgressBar()
    private let body = NSStackView()

    private var rows: [[Chip]] = []
    private var focus = (r: 0, c: 0)

    override init(frame f: NSRect) {
        super.init(frame: f)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true

        modePill.alignment = .right
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10

        let head = NSStackView(views: [title, modePill])
        head.orientation = .horizontal
        head.distribution = .fill
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let col = NSStackView(views: [head, sub, progressBar, body, footer])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 8
        col.translatesAutoresizingMaskIntoConstraints = false
        col.setHuggingPriority(.required, for: .vertical)
        addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.pad),
            col.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.pad),
            col.topAnchor.constraint(equalTo: topAnchor, constant: Theme.pad),
            col.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.pad),
            head.widthAnchor.constraint(equalTo: col.widthAnchor),
            progressBar.widthAnchor.constraint(equalTo: col.widthAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
        resetEmpty()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func text(_ size: CGFloat, _ weight: NSFont.Weight, faint: Bool = false) -> NSTextField {
        let t = NSTextField(labelWithString: "")
        t.font = .systemFont(ofSize: size, weight: weight)
        t.textColor = faint ? Theme.inkFaint : Theme.ink
        t.lineBreakMode = .byTruncatingMiddle
        return t
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 420, height: NSView.noIntrinsicMetric) }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    // MARK: paint

    override func draw(_ dirty: NSRect) {
        Theme.paper.setFill()
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: Theme.corner, yRadius: Theme.corner)
        card.fill()
        card.lineWidth = 1
        Theme.hairline.setStroke()
        card.stroke()

        if inputs.isEmpty {
            let dash = NSBezierPath(roundedRect: bounds.insetBy(dx: Theme.pad, dy: Theme.pad),
                                    xRadius: Theme.tileCorner, yRadius: Theme.tileCorner)
            dash.lineWidth = 1
            dash.setLineDash([5, 4], count: 2, phase: 0)
            Theme.hairline.setStroke()
            dash.stroke()
        }
    }

    // MARK: content

    private func resetEmpty() {
        inputs = []; formats = []; selectedTool = nil
        title.stringValue = "Drop files to convert"
        sub.stringValue = "images · video · audio · documents · archives"
        modePill.stringValue = ""
        footer.stringValue = "drop or ⌘V paste"
        progressBar.isHidden = true
        clearBody()
        owner?.fitToContent()
    }

    func accept(_ urls: [URL]) {
        inputs = urls
        formats = urls.compactMap { Formats.byURL($0) }
        selectedTool = nil
        running = false
        progress = 0
        progressBar.isHidden = true

        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        title.stringValue = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        let cats = Set(formats.map { $0.category.rawValue }).sorted().joined(separator: " · ")
        sub.stringValue = bytes > 0
            ? "\(cats)  ·  \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            : cats
        rebuild()
    }

    private var effectiveMode: Mode {
        if optionHeld { return .tools }
        return stickyMode ?? .convert
    }

    fileprivate func forceMode(_ name: String) {
        switch name {
        case "tools":   stickyMode = .tools
        case "recipes": stickyMode = .recipes
        default:        stickyMode = nil
        }
        if !inputs.isEmpty { rebuild() }
    }

    private func cycleMode() {
        let order = Mode.allCases
        let cur = stickyMode ?? .convert
        stickyMode = order[(order.firstIndex(of: cur)! + 1) % order.count]
        rebuild()
    }

    private func rebuild() {
        guard !inputs.isEmpty else { return }
        mode = effectiveMode
        modePill.stringValue = ["CONVERT", "TOOLS", "RECIPES"][Mode.allCases.firstIndex(of: mode)!]
        footer.stringValue = running ? "" : "↑↓←→ move   ↵ run   ⌥ tools   ⇥ mode   esc close"
        clearBody()
        rows = []

        switch mode {
        case .convert: buildConvert()
        case .tools:   buildTools()
        case .recipes: buildRecipes()
        }

        assignGrid()
        focus = (0, 0)
        refreshFocus()
        owner?.fitToContent()
    }

    private func clearBody() {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func rowStack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = Theme.tileGap
        s.alignment = .centerY
        return s
    }

    private func addChipRows(_ chips: [Chip], perRow: Int = 4, label: String? = nil) {
        if let label {
            let l = HUDView.text(10, .semibold, faint: true)
            l.stringValue = label.uppercased()
            body.addArrangedSubview(l)
        }
        var r = rowStack()
        for (i, chip) in chips.enumerated() {
            if i > 0 && i % perRow == 0 { body.addArrangedSubview(r); rows.append(currentRowChips(r)); r = rowStack() }
            r.addArrangedSubview(chip)
        }
        if !r.arrangedSubviews.isEmpty { body.addArrangedSubview(r); rows.append(currentRowChips(r)) }
    }

    private func currentRowChips(_ s: NSStackView) -> [Chip] { s.arrangedSubviews.compactMap { $0 as? Chip } }

    private func buildConvert() {
        let perFile = inputs.map { url -> Set<String> in
            guard let f = Formats.byURL(url) else { return [] }
            return Set(Engine.targets(for: f).map(\.id))
        }
        let shared = perFile.dropFirst().reduce(perFile.first ?? []) { $0.intersection($1) }
        let targets = shared.compactMap { Formats.byID[$0] }
            .filter { $0.id != "folder" || inputs.allSatisfy { Formats.byURL($0)?.category == .archive } }

        guard !targets.isEmpty else {
            let l = HUDView.text(11, .regular, faint: true)
            l.stringValue = "nothing converts this whole selection"
            body.addArrangedSubview(l)
            return
        }
        let groups = Category.allCases.compactMap { cat -> (Category, [Format])? in
            let fs = targets.filter { $0.category == cat }.sorted { $0.label < $1.label }
            return fs.isEmpty ? nil : (cat, fs)
        }
        for (cat, fs) in groups {
            let chips = fs.map { fmt -> Chip in
                let c = Chip(.format(fmt), title: fmt.label)
                c.onActivate = { [weak self] in self?.runConvert(to: fmt) }
                return c
            }
            addChipRows(chips, label: groups.count > 1 ? cat.rawValue : nil)
        }
    }

    private func buildTools() {
        let applicable = Tool.allCases.filter { $0.applies(to: formats, count: inputs.count) }
        guard !applicable.isEmpty else {
            let l = HUDView.text(11, .regular, faint: true)
            l.stringValue = "no tools for this selection"
            body.addArrangedSubview(l)
            return
        }
        let toolChips = applicable.map { t -> Chip in
            let c = Chip(.tool(t), title: t.label)
            c.selected = (t == selectedTool)
            c.onActivate = { [weak self] in self?.pickTool(t) }
            return c
        }
        addChipRows(toolChips, perRow: 3)

        if let t = selectedTool, !t.presets.isEmpty {
            let chips = t.presets.map { p -> Chip in
                let c = Chip(.preset(t, p), title: p.label)
                c.onActivate = { [weak self] in self?.runTool(t, preset: p) }
                return c
            }
            addChipRows(chips, perRow: 5)
        }
    }

    private func pickTool(_ t: Tool) {
        if t.presets.isEmpty { runTool(t, preset: nil); return }
        selectedTool = (selectedTool == t) ? nil : t
        rebuild()
    }

    private func buildRecipes() {
        let recipes = Recipes.all()
        guard !recipes.isEmpty else { return }
        let chips = recipes.map { r -> Chip in
            let c = Chip(.plain, title: r.name)
            c.onActivate = { [weak self] in self?.runRecipe(r) }
            return c
        }
        addChipRows(chips, perRow: 3)
    }

    private func runRecipe(_ recipe: Recipe) {
        let files = inputs
        run(count: files.count) { report in
            var first: URL?
            for (i, input) in files.enumerated() {
                let out = try RecipeRunner.run(recipe, input: input, into: nil)
                if first == nil { first = out }
                report(i + 1)
            }
            return (first, "\(recipe.name) · \(files.count)")
        }
    }

    // MARK: grid nav

    private func assignGrid() {
        for (ri, row) in rows.enumerated() {
            for (ci, chip) in row.enumerated() { chip.gridRow = ri; chip.gridCol = ci }
        }
    }

    private func chip(_ r: Int, _ c: Int) -> Chip? {
        guard rows.indices.contains(r) else { return nil }
        let row = rows[r]
        return row[min(max(0, c), row.count - 1)]
    }

    private func refreshFocus() {
        for row in rows { for chip in row { chip.focused = false } }
        chip(focus.r, focus.c)?.focused = true
    }

    private func move(dr: Int, dc: Int) {
        guard !rows.isEmpty else { return }
        var r = focus.r, c = focus.c
        if dc != 0 {
            c += dc
            if c < 0 { r -= 1; c = (rows[safe: r]?.count ?? 1) - 1 }
            else if c >= (rows[safe: r]?.count ?? 1) { r += 1; c = 0 }
        }
        if dr != 0 { r += dr }
        r = min(max(0, r), rows.count - 1)
        c = min(max(0, c), rows[r].count - 1)
        focus = (r, c)
        refreshFocus()
    }

    private func activateFocused() { chip(focus.r, focus.c)?.onActivate() }

    // MARK: run

    private func setChips(enabled: Bool) {
        for row in rows { for chip in row { chip.enabled = enabled } }
    }

    private func runConvert(to target: Format) {
        let files = inputs
        run(count: files.count) { report in
            var first: URL?
            for (i, input) in files.enumerated() {
                guard let out = Naming.output(for: input, target: target, into: nil, collision: .suffix) else { continue }
                if first == nil { first = out }
                try Engine.run(input: input, to: target, output: out, opts: ConvertOptions())
                report(i + 1)
            }
            return (first, "\(files.count) → \(target.label)")
        }
    }

    private func runTool(_ tool: Tool, preset: ToolPreset?) {
        let files = inputs
        let total = tool == .pdfMerge ? 1 : files.count
        run(count: total) { report in
            if tool == .pdfMerge || tool == .pdfSplit {
                let outs = try ToolRunner.run(tool, inputs: files, params: ToolRunner.Params(preset: preset))
                report(1)
                return (outs.first, tool.label)
            }
            var first: URL?
            for (i, input) in files.enumerated() {
                let outs = try ToolRunner.run(tool, inputs: [input], params: ToolRunner.Params(preset: preset))
                if first == nil { first = outs.first }
                report(i + 1)
            }
            return (first, "\(tool.label) · \(files.count)")
        }
    }

    /// Shared run harness: disables chips, drives the progress bar, reveals the
    /// result, closes on success.
    private func run(count: Int, _ work: @escaping (_ report: @escaping (Int) -> Void) throws -> (URL?, String)) {
        guard !running else { return }
        running = true
        setChips(enabled: false)
        progressBar.isHidden = false
        progress = 0
        footer.stringValue = ""
        let q = DispatchQueue(label: "kuori.run", qos: .userInitiated)
        q.async { [weak self] in
            let report: (Int) -> Void = { done in
                DispatchQueue.main.async { self?.progress = Double(done) / Double(max(1, count)) }
            }
            do {
                let (reveal, summary) = try work(report)
                DispatchQueue.main.async {
                    self?.progress = 1
                    self?.sub.stringValue = "done — \(summary)"
                    if let reveal { NSWorkspace.shared.activateFileViewerSelecting([reveal]) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.owner?.orderOut(nil); self?.finishRun() }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.sub.stringValue = error.localizedDescription
                    self?.progressBar.isHidden = true
                    self?.finishRun()
                }
            }
        }
    }

    private func finishRun() {
        running = false
        progress = 0
        setChips(enabled: true)
        footer.stringValue = "↑↓←→ move   ↵ run   ⌥ tools   esc close"
    }

    // MARK: keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: owner?.orderOut(nil)                       // esc
        case 123: move(dr: 0, dc: -1)                       // ←
        case 124: move(dr: 0, dc: +1)                       // →
        case 125: move(dr: +1, dc: 0)                       // ↓
        case 126: move(dr: -1, dc: 0)                       // ↑
        case 36, 76: activateFocused()                      // return / enter
        case 48: cycleMode()                               // tab
        default:
            if let ch = e.charactersIgnoringModifiers, ch == "v", e.modifierFlags.contains(.command) {
                pasteFiles()
            } else {
                super.keyDown(with: e)
            }
        }
    }

    override func flagsChanged(with e: NSEvent) {
        let held = e.modifierFlags.contains(.option)
        if held != optionHeld {
            optionHeld = held
            if !inputs.isEmpty { rebuild() }
        }
        super.flagsChanged(with: e)
    }

    private func pasteFiles() {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            accept(urls)
        }
    }

    // MARK: drag

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return false }
        accept(urls)
        return true
    }
}

private final class ProgressBar: NSView {
    var fraction: Double = 0
    override func draw(_ dirty: NSRect) {
        Theme.hairline.withAlphaComponent(0.4).setFill()
        bounds.fill()
        Theme.ink.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(1, fraction))), height: bounds.height).fill()
    }
}

